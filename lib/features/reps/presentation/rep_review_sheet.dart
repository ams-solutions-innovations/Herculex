import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../domain/rep_suggestion.dart';
import 'rep_tracking_providers.dart';

/// Callback [RepReviewSheet]'s "Save set" action invokes with **the values
/// currently in the fields at save time** — not necessarily
/// `suggestion.proposedReps`. Injected by `active_exercise_card.dart`, which
/// owns the existing user-driven set-completion handler this wraps.
typedef RepConfirmCallback = Future<void> Function(int reps, int? rpeX10);

/// The editable, pre-filled review sheet the user sees when ending a
/// tracked set — before anything is written.
///
/// **Import discipline (REP-03):** this file imports nothing from
/// `lib/features/workouts/` — not `data/`, not `domain/`, not
/// `presentation/`. It does not know `updateSet`, `WorkoutsRepository` or
/// `SetEntriesCompanion` exist. Its entire route to the write path is
/// [onConfirm].
class RepReviewSheet extends ConsumerStatefulWidget {
  const RepReviewSheet({
    super.key,
    required this.suggestion,
    required this.onConfirm,
    required this.sessionId,
    this.setEntryId,
  });

  final RepSuggestion suggestion;
  final RepConfirmCallback onConfirm;

  /// `RepSuggestion` carries no session/set identity (10-03b's contract),
  /// but `recordObservation` requires it — the caller supplies both so the
  /// sheet can log the observation itself after a successful [onConfirm].
  final int sessionId;
  final int? setEntryId;

  static Future<void> show(
    BuildContext context, {
    required RepSuggestion suggestion,
    required RepConfirmCallback onConfirm,
    required int sessionId,
    int? setEntryId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RepReviewSheet(
        suggestion: suggestion,
        onConfirm: onConfirm,
        sessionId: sessionId,
        setEntryId: setEntryId,
      ),
    );
  }

  @override
  ConsumerState<RepReviewSheet> createState() => _RepReviewSheetState();
}

class _RepReviewSheetState extends ConsumerState<RepReviewSheet> {
  late final TextEditingController _repsCtrl;
  double? _rpe;
  bool _saving = false;
  bool _measurementExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repsCtrl = TextEditingController(
      text: widget.suggestion.proposedReps.toString(),
    );
  }

  @override
  void dispose() {
    _repsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reps = int.tryParse(_repsCtrl.text) ?? widget.suggestion.proposedReps;
    final rpeX10 = _rpe == null ? null : (_rpe! * 10).round();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // The set is written first — only after it returns does anything
      // touch the observation table (plan requirement: order matters).
      await widget.onConfirm(reps, rpeX10);
    } catch (e) {
      // If onConfirm throws, no observation is recorded either — the set
      // was never actually written.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save set: $e';
        });
      }
      return;
    }

    await ref
        .read(repTrackingRepositoryProvider)
        .recordObservation(
          exerciseSlug: widget.suggestion.exerciseSlug,
          sessionId: widget.sessionId,
          setEntryId: widget.setEntryId,
          recordedAt: DateTime.now(),
          source: widget.suggestion.source,
          placement: widget.suggestion.placement,
          sensorType: widget.suggestion.sensorType,
          detectedReps: widget.suggestion.proposedReps,
          confirmedReps: reps,
          confidence: widget.suggestion.setConfidence,
          // 10-05 owns the RPE-suggestion gate; nothing suggests one yet.
          suggestedRpeX10: null,
          confirmedRpeX10: rpeX10,
          featuresJson: jsonEncode(widget.suggestion.featuresJson ?? const {}),
        );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.suggestion;
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Review this set',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Edit anything that looks wrong before saving — nothing is '
                'written until you tap Save.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (s.provisionalDisagrees) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'The watch and the phone-side detector disagreed on this '
                    'set. The count below is the authoritative one; confidence '
                    'has already been lowered.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _repsCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Reps',
                        filled: true,
                        fillColor: AppColors.surfaceContainer,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _ConfidenceBadge(
                    band: s.confidenceBand,
                    confidence: s.setConfidence,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'RPE (optional)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _rpe ?? 8.0,
                      min: 5.0,
                      max: 10.0,
                      divisions: 10,
                      label: _rpe?.toStringAsFixed(1) ?? 'Not set',
                      onChanged: (v) => setState(() => _rpe = v),
                    ),
                  ),
                  if (_rpe != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear RPE',
                      onPressed: () => setState(() => _rpe = null),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _measurementExpanded,
                onExpansionChanged: (v) =>
                    setState(() => _measurementExpanded = v),
                title: Text(
                  'How this was measured',
                  style: theme.textTheme.labelMedium,
                ),
                children: [
                  _measurementRow('Source', s.source),
                  if (s.placement != null)
                    _measurementRow('placement', s.placement!),
                  _measurementRow('Sensor', s.sensorType),
                  _measurementRow(
                    'Sample coverage',
                    '${(s.coverageRatio * 100).round()}%'
                        '${s.missedBatches > 0 ? ' (${s.missedBatches} missed batches)' : ''}',
                  ),
                  _measurementRow(
                    'Calibration applied',
                    s.features != null ? 'yes' : 'no',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save set'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _measurementRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.secondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.band, required this.confidence});

  final ConfidenceBand band;
  final double confidence;

  Color get _color => switch (band) {
    ConfidenceBand.high => Colors.green,
    ConfidenceBand.medium => Colors.amber,
    ConfidenceBand.low => Colors.orange,
  };

  String get _label => switch (band) {
    ConfidenceBand.high => 'High',
    ConfidenceBand.medium => 'Medium',
    ConfidenceBand.low => 'Low',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label,
            style: TextStyle(color: _color, fontWeight: FontWeight.bold),
          ),
          Text(
            '${(confidence * 100).round()}%',
            style: TextStyle(color: _color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
