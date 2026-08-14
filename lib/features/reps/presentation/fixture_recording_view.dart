import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../widgets/glass_container.dart';
import '../data/fixture_recorder.dart';
import '../data/phone_motion_source.dart';
import '../domain/fixture_corpus.dart';
import '../domain/motion_sample.dart';
import 'rep_tracking_providers.dart';

/// **Debug-only.** In-app tool that replaces the manual "record on hardware,
/// hand-copy CSVs" procedure from `10-02-PLAN.md` Task 5 with a checklist and
/// capture flow, so the developer can record the 11-fixture REP-06 corpus
/// opportunistically across real workouts.
///
/// Reachable only from the debug-only admin area, at `/admin/fixture-recording`
/// (same release-exclusion convention as the rest of `/admin/*`).
///
/// **This screen does not close REP-06.** It writes files under this app's
/// private documents directory, not into the repo's `test/fixtures/motion/`
/// — the developer exports them via "Export recorded fixtures" and commits
/// them by hand. 10-02's `test/rep_fixture_provenance_test.dart` remains the
/// actual automated gate.
class FixtureRecordingView extends ConsumerStatefulWidget {
  const FixtureRecordingView({super.key});

  @override
  ConsumerState<FixtureRecordingView> createState() => _FixtureRecordingViewState();
}

class _FixtureRecordingViewState extends ConsumerState<FixtureRecordingView> {
  final FixtureRecorder _recorder = FixtureRecorder();
  Future<FixtureCorpusStatus>? _statusFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _statusFuture =
          _recorder.listRecorded().then(FixtureCorpusStatus.evaluate);
    });
  }

  Future<void> _export() async {
    final files = await _recorder.allFixtureFiles();
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fixtures recorded yet.')),
      );
      return;
    }
    await Share.shareXFiles(
      [for (final f in files) XFile(f.path)],
      text: 'Herculex REP-06 fixture corpus — commit under test/fixtures/motion/',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Fixture Recording', style: theme.textTheme.labelLarge),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export recorded fixtures',
            onPressed: _export,
          ),
        ],
      ),
      body: FutureBuilder<FixtureCorpusStatus>(
        future: _statusFuture,
        builder: (context, snapshot) {
          final status = snapshot.data;
          if (status == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final recordedCount = status.byName.values
              .where((s) => s == FixtureRecordState.recorded)
              .length;

          return ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              GlassContainer(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      status.sufficient ? Icons.check_circle : Icons.pending_outlined,
                      color: status.sufficient ? Colors.green : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        status.sufficient
                            ? '11/11 recorded — corpus complete'
                            : '${11 - recordedCount} missing — $recordedCount/11 recorded',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This tool does not close REP-06. Export and commit the files '
                'under test/fixtures/motion/ by hand once the corpus is complete.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              for (final spec in requiredFixtures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FixtureRow(
                    spec: spec,
                    state: status.byName[spec.name] ?? FixtureRecordState.missing,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _FixtureCaptureScreen(
                            spec: spec,
                            recorder: _recorder,
                          ),
                        ),
                      );
                      _refresh();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FixtureRow extends StatelessWidget {
  const _FixtureRow({required this.spec, required this.state, required this.onTap});

  final FixtureSpec spec;
  final FixtureRecordState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorded = state == FixtureRecordState.recorded;

    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              recorded ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              color: recorded ? Colors.green : theme.colorScheme.secondary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.name, style: theme.textTheme.labelLarge?.copyWith(fontSize: 14)),
                  Text(
                    '${spec.purpose} — ${spec.source}'
                    '${spec.placement != null ? '/${spec.placement}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: theme.textTheme.bodyMedium?.color),
          ],
        ),
      ),
    );
  }
}

/// Per-fixture capture form: read-only movement/source/placement, editable
/// description/recordedBy/deviceModel, and a ground-truth `repCount` number
/// field labelled as human-counted, never detector-derived.
class _FixtureCaptureScreen extends ConsumerStatefulWidget {
  const _FixtureCaptureScreen({required this.spec, required this.recorder});

  final FixtureSpec spec;
  final FixtureRecorder recorder;

  @override
  ConsumerState<_FixtureCaptureScreen> createState() => _FixtureCaptureScreenState();
}

class _FixtureCaptureScreenState extends ConsumerState<_FixtureCaptureScreen> {
  final _descriptionController = TextEditingController();
  final _recordedByController = TextEditingController();
  final _deviceModelController = TextEditingController();
  final _repCountController = TextEditingController();

  bool _capturing = false;
  bool _saved = false;
  StreamSubscription<PhoneMotionCaptureResult>? _phoneEndSub;

  @override
  void dispose() {
    // Belt-and-braces: a capture left running when this screen is popped
    // must never keep observing after the screen is gone.
    if (widget.spec.source == 'wrist') {
      ref.read(repCaptureServiceProvider).debugRawTraceObserver = null;
    }
    _phoneEndSub?.cancel();
    _descriptionController.dispose();
    _recordedByController.dispose();
    _deviceModelController.dispose();
    _repCountController.dispose();
    super.dispose();
  }

  int? get _repCount => int.tryParse(_repCountController.text.trim());

  Future<void> _saveTrace(MotionTrace trace) async {
    final repCount = _repCount;
    if (repCount == null) return;
    await widget.recorder.save(
      widget.spec.name,
      trace,
      repCount: repCount,
      movement: widget.spec.movement,
      source: widget.spec.source,
      placement: widget.spec.placement,
      description: _descriptionController.text.trim(),
      recordedBy: _recordedByController.text.trim(),
      deviceModel: _deviceModelController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.spec.name} saved.')),
    );
  }

  Future<void> _start() async {
    final repCount = _repCount;
    if (repCount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the human-counted rep count before starting.')),
      );
      return;
    }

    setState(() => _capturing = true);

    if (widget.spec.source == 'wrist') {
      // The watch itself starts wrist capture (10-CONTEXT — capture begins
      // from the user's own tap on the watch). This screen only arms the
      // debug observer so the next capture_end this service sees is saved as
      // this fixture, then disarms it immediately after — see the doc
      // comment on RepCaptureService.debugRawTraceObserver.
      ref.read(repCaptureServiceProvider).debugRawTraceObserver = (captureId, trace) {
        unawaited(_saveTrace(trace));
      };
    } else {
      final refusal = await ref.read(phoneMotionSourceProvider).start();
      if (refusal != null && mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(refusal.reason)),
        );
        return;
      }
      _phoneEndSub = ref.read(phoneMotionSourceProvider).captureEnded.listen((result) {
        unawaited(_saveTrace(result.trace));
      });
    }
  }

  Future<void> _stop() async {
    if (widget.spec.source == 'wrist') {
      // Reset immediately after stop, per the field's own doc comment — no
      // capture outside this screen's own window is ever observed.
      ref.read(repCaptureServiceProvider).debugRawTraceObserver = null;
    } else {
      ref.read(phoneMotionSourceProvider).stop();
      await _phoneEndSub?.cancel();
      _phoneEndSub = null;
    }
    if (mounted) setState(() => _capturing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;

    return Scaffold(
      appBar: AppBar(
        title: Text(spec.name, style: theme.textTheme.labelLarge),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.purpose, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text('Movement: ${spec.movement?.name ?? 'none (noise fixture)'}'),
                Text('Source: ${spec.source}'),
                Text('Placement: ${spec.placement ?? 'n/a'}'),
                Text('Target rep count: ${spec.targetRepCount}'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _repCountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Ground-truth rep count',
              helperText: 'Count out loud or film the set. Enter the HUMAN count — '
                  'never the app\'s detected or provisional count.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _recordedByController,
            decoration: const InputDecoration(labelText: 'Recorded by'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _deviceModelController,
            decoration: const InputDecoration(
              labelText: 'Device model',
              helperText: 'Exact watch or phone model string, typed by hand.',
            ),
          ),
          const SizedBox(height: 24),
          if (widget.spec.source == 'wrist')
            Text(
              'Start the capture on your watch as usual once you tap Start below.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _capturing ? null : _start,
                  child: const Text('Start'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: _capturing ? _stop : null,
                  child: const Text('Stop'),
                ),
              ),
            ],
          ),
          if (_saved) ...[
            const SizedBox(height: 16),
            Text('Saved.', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green)),
          ],
        ],
      ),
    );
  }
}
