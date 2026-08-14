package com.ams.herculex.sync

object WearSyncPaths {
    // Phone -> watch durable state. Watch -> phone uses a SEPARATE path
    // (STATE_WATCH_ACTIVE_WORKOUT) below — DataClient's onDataChanged fires
    // on the writer's own node too, so sharing one path bidirectionally would
    // make each side re-process its own writes as if they came from the peer.
    const val STATE_ACTIVE_WORKOUT = "/herculex/state/active_workout"
    const val STATE_WATCH_ACTIVE_WORKOUT = "/herculex/state/watch_active_workout"
    const val STATE_MACRO_TARGETS = "/herculex/state/macro_targets"
    const val STATE_FASTING = "/herculex/state/fasting"
    const val STATE_USER_TOKEN = "/herculex/state/user_token"

    // These must stay under the "/herculex" prefix — the watch manifest's
    // MESSAGE_RECEIVED intent-filter only matches that prefix, so anything
    // outside it is silently undeliverable (see LESSONS.md).
    const val MESSAGE_START_REST_TIMER = "/herculex/workout/start_rest_timer"
    const val MESSAGE_UPDATE_WEIGHT = "/herculex/workout/update_weight"
    const val MESSAGE_FINISH_WORKOUT = "/herculex/workout/finish"

    // Assisted rep tracking (watch -> phone). Raw accelerometer samples are
    // batched roughly 1 s per MESSAGE_REP_SAMPLES and never leave the paired
    // device pair. The provisionalCount carried on MESSAGE_REP_CAPTURE_END is
    // NON-AUTHORITATIVE — the phone's Dart detector owns the proposed count.
    const val MESSAGE_REP_CAPTURE_START = "/herculex/reps/capture_start"
    const val MESSAGE_REP_SAMPLES = "/herculex/reps/samples"
    const val MESSAGE_REP_CAPTURE_END = "/herculex/reps/capture_end"

    // Fast-path (MessageClient) active-session sync — near-instant, requires a
    // connected node. DataClient STATE_ACTIVE_WORKOUT above remains the
    // durable fallback used to catch a peer up on reconnect.
    const val MESSAGE_ACTIVE_SESSION_START = "/herculex_active_session_start"
    const val MESSAGE_ACTIVE_SESSION_UPDATE = "/herculex_active_session_update"
    const val MESSAGE_ACTIVE_SESSION_END = "/herculex_active_session_end"
    const val MESSAGE_FASTING_SNAPSHOT = "/herculex_fasting_snapshot"

    // Fast-path (MessageClient) watch → phone session update — mirrors the
    // legacy DataClient path so both directions get the same low-latency
    // treatment.
    const val MESSAGE_WATCH_SESSION_STARTED = "/herculex_watch_workout_started"
    const val MESSAGE_WATCH_SESSION_UPDATE = "/herculex_watch_session_update"
    const val MESSAGE_WATCH_SESSION_END = "/herculex_watch_session_end"
    const val MESSAGE_WATCH_SESSION_DISCARD = "/herculex_watch_session_discard"
    const val MESSAGE_FASTING_COMMAND = "/herculex_fasting_command"
    const val MESSAGE_FASTING_ACK = "/herculex_fasting_ack"
    const val MESSAGE_QUICKADD_COMMAND = "/herculex_quickadd_command"
    const val MESSAGE_QUICKADD_ACK = "/herculex_quickadd_ack"
    const val MESSAGE_MACRO_COMMAND = "/herculex_macro_command"
    const val MESSAGE_MACRO_ACK = "/herculex_macro_ack"
}
