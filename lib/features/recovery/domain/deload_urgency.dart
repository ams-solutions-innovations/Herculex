/// Shared across [MuscleDeloadAdvisor], the joint-stress advisor, and the
/// training-suggestion engine, so the Recovery page can render one
/// badge/color scheme for "should this be backed off" everywhere it appears.
enum DeloadUrgency { none, watch, recommended }
