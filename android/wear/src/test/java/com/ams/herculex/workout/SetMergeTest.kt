package com.ams.herculex.workout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * The conflict rule between phone and watch: for each of weight, reps and
 * completion the side with the newer stamp wins, with no device priority.
 *
 * The property tests at the bottom are what actually rule out ping-pong:
 * if the merge is idempotent, commutative and associative, any delivery order
 * (late, duplicated, crossed in flight) leaves both devices in the same state,
 * and applying a snapshot never produces a *new* stamp that would have to be
 * sent back.
 */
class SetMergeTest {

    private val phone = "phone"
    private val watch = "watch"

    private fun stamp(revision: Long, origin: String) = SetSyncStamp(revision, origin)

    private fun set(
        weight: Double,
        weightStamp: SetSyncStamp,
        reps: Int = 8,
        repsStamp: SetSyncStamp = weightStamp,
        completed: Boolean = false,
        completionStamp: SetSyncStamp = weightStamp,
    ) = LoggedSet(
        wireId = "set_1",
        weight = weight,
        reps = reps,
        completed = completed,
        syncVersions = SetSyncVersions(weightStamp, repsStamp, completionStamp),
    )

    @Test
    fun `a newer remote weight replaces the local one`() {
        val local = set(80.0, stamp(100, watch))
        val remote = set(85.0, stamp(200, phone))

        val merged = mergeRemoteSet(local, remote)

        assertEquals(85.0, merged.weight, 0.0)
        assertEquals(stamp(200, phone), merged.syncVersions!!.weight)
    }

    @Test
    fun `a stale snapshot cannot overwrite a newer local weight`() {
        val local = set(90.0, stamp(300, watch))
        val remote = set(80.0, stamp(200, phone))

        val merged = mergeRemoteSet(local, remote)

        assertEquals(90.0, merged.weight, 0.0)
        assertEquals(stamp(300, watch), merged.syncVersions!!.weight)
    }

    @Test
    fun `weight reps and completion are decided independently`() {
        // The phone's snapshot is older for weight and reps but its completion
        // is the newest action on the set.
        val local = set(
            weight = 90.0, weightStamp = stamp(300, watch),
            reps = 10, repsStamp = stamp(300, watch),
            completed = false, completionStamp = stamp(100, watch),
        )
        val remote = set(
            weight = 80.0, weightStamp = stamp(200, phone),
            reps = 8, repsStamp = stamp(200, phone),
            completed = true, completionStamp = stamp(400, phone),
        )

        val merged = mergeRemoteSet(local, remote)

        assertEquals(90.0, merged.weight, 0.0)
        assertEquals(10, merged.reps)
        assertTrue(merged.completed)
    }

    @Test
    fun `an exact revision tie is decided the same way on both devices`() {
        val onPhone = set(80.0, stamp(100, phone))
        val onWatch = set(90.0, stamp(100, watch))

        // Each device merges the other's snapshot into its own copy.
        val phoneAfter = mergeRemoteSet(local = onPhone, remote = onWatch)
        val watchAfter = mergeRemoteSet(local = onWatch, remote = onPhone)

        assertEquals(phoneAfter.weight, watchAfter.weight, 0.0)
        assertEquals(phoneAfter.syncVersions, watchAfter.syncVersions)
    }

    @Test
    fun `a snapshot without field versions replaces the set wholesale`() {
        val local = set(80.0, stamp(100, watch))
        val legacy = LoggedSet(wireId = "set_1", weight = 70.0, reps = 5, completed = false)

        assertEquals(legacy, mergeRemoteSet(local, legacy))
    }

    @Test
    fun `every differing field is reported with the side that was kept`() {
        val local = set(
            weight = 90.0, weightStamp = stamp(300, watch),
            reps = 8, repsStamp = stamp(100, watch),
        )
        val remote = set(
            weight = 80.0, weightStamp = stamp(200, phone),
            reps = 12, repsStamp = stamp(200, phone),
        )
        val decisions = mutableListOf<Triple<String, Long, Boolean>>()

        mergeRemoteSet(local, remote) { field, remoteStamp, _, keptRemote ->
            decisions += Triple(field, remoteStamp.revision, keptRemote)
        }

        assertEquals(
            listOf(Triple("weight", 200L, false), Triple("reps", 200L, true)),
            decisions,
        )
    }

    @Test
    fun `merging identical values stays silent`() {
        val local = set(80.0, stamp(100, watch))
        val remote = set(80.0, stamp(200, phone))
        var calls = 0

        mergeRemoteSet(local, remote) { _, _, _, _ -> calls++ }

        assertEquals(0, calls)
    }

    // ── Convergence properties ────────────────────────────────────────────────

    // A stamp identifies exactly one value, as it does in production, where an
    // allocator never issues the same (revision, origin) twice. Without this
    // the generator would invent equal stamps with different values, which can
    // never happen on a real device.
    private fun valueFor(s: SetSyncStamp) = s.revision * 10 + if (s.origin == phone) 1 else 2

    private fun randomSet(random: Random): LoggedSet {
        fun randomStamp() = SetSyncStamp(
            revision = random.nextLong(1, 6), // few revisions, so ties are common
            origin = if (random.nextBoolean()) phone else watch,
        )
        val weight = randomStamp()
        val reps = randomStamp()
        val completion = randomStamp()
        return LoggedSet(
            wireId = "set_1",
            weight = valueFor(weight).toDouble(),
            reps = valueFor(reps).toInt(),
            completed = valueFor(completion) % 2 == 0L,
            completedAtEpochMs = valueFor(completion),
            syncVersions = SetSyncVersions(weight, reps, completion),
        )
    }

    @Test
    fun `merge is commutative idempotent and associative for any delivery order`() {
        val random = Random(20261007)
        repeat(3000) {
            val a = randomSet(random)
            val b = randomSet(random)
            val c = randomSet(random)

            val ab = mergeRemoteSet(a, b)
            assertEquals("commutative", ab, mergeRemoteSet(b, a))
            assertEquals("idempotent (redelivery)", ab, mergeRemoteSet(ab, b))
            assertEquals("idempotent (own state)", ab, mergeRemoteSet(ab, a))
            assertEquals(
                "associative",
                mergeRemoteSet(mergeRemoteSet(a, b), c),
                mergeRemoteSet(a, mergeRemoteSet(b, c)),
            )
        }
    }

    @Test
    fun `merging never mints a stamp that was not already on one side`() {
        val random = Random(7)
        repeat(3000) {
            val local = randomSet(random)
            val remote = randomSet(random)

            val merged = mergeRemoteSet(local, remote).syncVersions!!
            val l = local.syncVersions!!
            val r = remote.syncVersions!!

            assertTrue(merged.weight == l.weight || merged.weight == r.weight)
            assertTrue(merged.reps == l.reps || merged.reps == r.reps)
            assertTrue(merged.completion == l.completion || merged.completion == r.completion)
        }
    }
}
