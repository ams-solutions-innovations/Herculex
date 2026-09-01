import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:herculex/core/error/error_log.dart';
import 'package:herculex/theme/tokens/tokens.dart';
import 'package:herculex/ui/ui.dart';

/// Read-only view of [ErrorLog].
///
/// Registered outside the router's `kDebugMode` block on purpose: a release
/// build is exactly where an error is otherwise invisible — the release
/// `ErrorWidget` is a blank box and nothing is reported anywhere — so this
/// needs to be reachable there too.
class ErrorLogView extends StatelessWidget {
  const ErrorLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;

    return HxScreenShell(
      title: 'Error Log',
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Clear',
          onPressed: ErrorLog.instance.clear,
        ),
      ],
      children: [
        ValueListenableBuilder<int>(
          valueListenable: ErrorLog.instance.revision,
          builder: (context, _, _) {
            final records = ErrorLog.instance.records;
            if (records.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No errors recorded.',
                    style: TextStyle(color: hx.onSurfaceVariant),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < records.length; i++) ...[
                  if (i > 0) const SizedBox(height: HxSpace.x3),
                  _RecordCard(record: records[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final AppErrorRecord record;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final t = record.time;
    final stamp =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';

    return HxCard(
      padding: const EdgeInsets.all(HxSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                record.source.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: hx.primary,
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Text(
                stamp,
                style: TextStyle(fontSize: 11, color: hx.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy',
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text:
                        '${record.source} $stamp\n${record.summary}\n'
                        '${record.details ?? ''}\n${record.stack ?? ''}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x2),
          SelectableText(
            record.summary,
            style: TextStyle(fontSize: 13, color: hx.onSurface),
          ),
          if (record.details != null) ...[
            const SizedBox(height: HxSpace.x1),
            Text(
              record.details!,
              style: TextStyle(fontSize: 11, color: hx.onSurfaceVariant),
            ),
          ],
          if (record.stack != null) ...[
            const SizedBox(height: HxSpace.x2),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Stack trace',
                style: TextStyle(fontSize: 12, color: hx.onSurfaceVariant),
              ),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    record.stack!,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: hx.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
