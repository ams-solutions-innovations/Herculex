package com.ams.herculex.workout

/// Per-field "last change wins" merge of a set received from the phone into
/// the watch's own copy. No device has priority: each of weight, reps and
/// completion keeps whichever side carries the newer [SetSyncStamp], and an
/// exact tie is broken by origin so both devices make the same decision.
///
/// Pure on purpose (no Android types) so the conflict rules can be unit
/// tested. [onDifference] is called once per field where the two sides hold
/// different values, saying which one was kept; a merge of identical values
/// stays silent. The envelope log only ever said `apply=accepted`, which hid
/// every field-level rejection.
internal fun mergeRemoteSet(
    local: LoggedSet,
    remote: LoggedSet,
    onDifference: (field: String, remote: SetSyncStamp, local: SetSyncStamp, keptRemote: Boolean) -> Unit =
        { _, _, _, _ -> },
): LoggedSet {
    // Legacy sessions have no field metadata. The remote session is the
    // best available truth in that case; all current protocol peers send
    // versions so later messages use the safe path below.
    val localVersions = local.syncVersions ?: return remote
    val remoteVersions = remote.syncVersions ?: return remote

    val useRemoteWeight = remoteVersions.weight > localVersions.weight
    val useRemoteReps = remoteVersions.reps > localVersions.reps
    val useRemoteCompletion = remoteVersions.completion > localVersions.completion

    if (remote.weight != local.weight) {
        onDifference("weight", remoteVersions.weight, localVersions.weight, useRemoteWeight)
    }
    if (remote.reps != local.reps) {
        onDifference("reps", remoteVersions.reps, localVersions.reps, useRemoteReps)
    }
    if (remote.completed != local.completed) {
        onDifference("completion", remoteVersions.completion, localVersions.completion, useRemoteCompletion)
    }

    return remote.copy(
        weight = if (useRemoteWeight) remote.weight else local.weight,
        reps = if (useRemoteReps) remote.reps else local.reps,
        completed = if (useRemoteCompletion) remote.completed else local.completed,
        completedAtEpochMs = if (useRemoteCompletion) {
            remote.completedAtEpochMs
        } else {
            local.completedAtEpochMs
        },
        syncVersions = SetSyncVersions(
            weight = if (useRemoteWeight) remoteVersions.weight else localVersions.weight,
            reps = if (useRemoteReps) remoteVersions.reps else localVersions.reps,
            completion = if (useRemoteCompletion) {
                remoteVersions.completion
            } else {
                localVersions.completion
            },
        ),
    )
}
