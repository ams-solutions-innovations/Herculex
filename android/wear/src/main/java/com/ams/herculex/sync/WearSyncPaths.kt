package com.ams.herculex.sync

object WearSyncPaths {
    // Phone -> watch durable state. Watch -> phone uses a SEPARATE path
    // (STATE_WATCH_ACTIVE_WORKOUT) below — DataClient's onDataChanged fires
    // on the writer's own node too, so sharing one path bidirectionally would
    // make each side re-process its own writes as if they came from the peer.
    const val STATE_ACTIVE_WORKOUT = "/herculex/state/active_workout"
    const val STATE_WATCH_ACTIVE_WORKOUT = "/herculex/state/watch_active_workout"
    const val STATE_MACRO_TARGETS = "/herculex/state/macro_targets"
    const val STATE_USER_TOKEN = "/herculex/state/user_token"

    const val MESSAGE_START_REST_TIMER = "/workout/start_rest_timer"
    const val MESSAGE_UPDATE_WEIGHT = "/workout/update_weight"
    const val MESSAGE_FINISH_WORKOUT = "/workout/finish"

    // Fast-path (MessageClient) active-session sync — near-instant, requires a
    // connected node. DataClient STATE_ACTIVE_WORKOUT above remains the
    // durable fallback used to catch a peer up on reconnect.
    const val MESSAGE_ACTIVE_SESSION_START = "/herculex_active_session_start"
    const val MESSAGE_ACTIVE_SESSION_UPDATE = "/herculex_active_session_update"
    const val MESSAGE_ACTIVE_SESSION_END = "/herculex_active_session_end"

    // Fast-path (MessageClient) watch → phone session update — mirrors the
    // legacy DataClient path so both directions get the same low-latency
    // treatment.
    const val MESSAGE_WATCH_SESSION_STARTED = "/herculex_watch_workout_started"
    const val MESSAGE_WATCH_SESSION_UPDATE = "/herculex_watch_session_update"
    const val MESSAGE_WATCH_SESSION_END = "/herculex_watch_session_end"
}
