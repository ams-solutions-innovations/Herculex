import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class LabsPdfService {
  Future<Uint8List> render(LabsSnapshot snapshot) async {
    final body = await rootBundle.load('assets/fonts/Manrope-Variable.ttf');
    final heading = await rootBundle.load(
      'assets/fonts/SpaceGrotesk-Variable.ttf',
    );
    return compute(_renderLabsPdf, (
      snapshot,
      body.buffer.asUint8List(body.offsetInBytes, body.lengthInBytes),
      heading.buffer.asUint8List(heading.offsetInBytes, heading.lengthInBytes),
    ));
  }

  static List<double> _ticks(List<double> values) {
    values.sort();
    var lo = values.first, hi = values.last;
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    return [lo, (lo + hi) / 2, hi];
  }

  Future<File> save(LabsSnapshot snapshot) async {
    final dir = await directory();
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/labs-${snapshot.period.id}-r${snapshot.revision}.pdf',
    );
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(await render(snapshot), flush: true);
    return temp.rename(file.path);
  }

  Future<Directory> directory() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/labs');
  Future<void> deleteFiles() async {
    final dir = await directory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

String _experimentSummary(Map<String, dynamic> e) {
  final r = e['evaluation'] as Map?;
  if (r == null) return 'Collecting observations.';
  return '${r['state']} / baseline ${(r['before'] as num?)?.toStringAsFixed(1) ?? 'unknown'} / change ${(r['after'] as num?)?.toStringAsFixed(1) ?? 'unknown'} ${e['unit']}\n${r['limitation']}';
}

Future<Uint8List> _renderLabsPdf(
  (LabsSnapshot, Uint8List, Uint8List) input,
) async {
  final snapshot = input.$1;
  final font = pw.Font.ttf(ByteData.sublistView(input.$2));
  final display = pw.Font.ttf(ByteData.sublistView(input.$3));
  final doc = pw.Document(title: 'Herculex Labs', author: 'Herculex');
  final accent = PdfColor.fromHex('#157DAD');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(base: font, bold: display),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: accent)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'HERCULEX / LABS',
              style: pw.TextStyle(font: display, color: accent, fontSize: 16),
            ),
            pw.Text('PRIVATE / LOCAL', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
      footer: (c) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'labs-1 / revision ${snapshot.revision} / ${c.pageNumber} of ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        pw.SizedBox(height: 18),
        pw.Text(
          'Your personal progress report',
          style: pw.TextStyle(font: display, fontSize: 26),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '${labsDate(snapshot.period.start)} - ${labsDate(DateTime(snapshot.period.end.year, snapshot.period.end.month, snapshot.period.end.day - 1))}',
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          snapshot.partial
              ? 'Partial first period: tracking began during this reporting window.'
              : 'Completed reporting period.',
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Personal summary',
          style: pw.TextStyle(font: display, fontSize: 18),
        ),
        ...snapshot.findings
            .where((f) => f.delta != null || f.q != null)
            .take(3)
            .map(
              (f) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Text('${f.title}: ${f.detail}'),
              ),
            ),
        if (!snapshot.findings.any((f) => f.delta != null || f.q != null))
          pw.Text(
            'Still building your baseline. Recorded observations appear below; there is not enough evidence for a supported comparison.',
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Observations describe patterns, not proof of cause. Missing records remain unknown. Associations use up to 180 days before the period boundary.',
        ),
        ...LabsCategory.values
            .where(
              (c) => snapshot.findings.any(
                (f) => f.category == c && f.points.isNotEmpty,
              ),
            )
            .expand(
              (category) => [
                pw.SizedBox(height: 18),
                pw.Text(
                  category.label,
                  style: pw.TextStyle(
                    font: display,
                    fontSize: 18,
                    color: accent,
                  ),
                ),
                ...snapshot.findings
                    .where((f) => f.category == category)
                    .expand(
                      (f) => [
                        pw.SizedBox(height: 10),
                        pw.Text(
                          f.title,
                          style: pw.TextStyle(font: display, fontSize: 12),
                        ),
                        pw.Text(
                          '${f.support} / ${f.n} observed days / ${(f.coverage * 100).round()}% calendar coverage',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          f.detail,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (f.points.length > 1)
                          pw.SizedBox(
                            height: 105,
                            child: pw.Chart(
                              grid: pw.CartesianGrid(
                                xAxis: pw.FixedAxis(
                                  [
                                    0,
                                    _chartDay(
                                      f.points.last.at,
                                      f.points.first.at,
                                    ),
                                  ],
                                  format: (v) => labsDate(
                                    DateTime(
                                      f.points.first.at.year,
                                      f.points.first.at.month,
                                      f.points.first.at.day + v.round(),
                                    ),
                                  ).substring(5),
                                  textStyle: const pw.TextStyle(fontSize: 8),
                                ),
                                yAxis: pw.FixedAxis(
                                  LabsPdfService._ticks(
                                    f.points.map((p) => p.value).toList(),
                                  ),
                                  textStyle: const pw.TextStyle(fontSize: 8),
                                ),
                              ),
                              datasets: [
                                pw.LineDataSet(
                                  color: accent,
                                  drawPoints: false,
                                  data: [
                                    for (var i = 0; i < f.points.length; i++)
                                      pw.PointChartValue(
                                        _chartDay(
                                          f.points[i].at,
                                          f.points.first.at,
                                        ),
                                        f.points[i].value,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (f.intervalLow != null)
                          pw.Text(
                            'Association 95% interval: ${f.intervalLow!.toStringAsFixed(2)} to ${f.intervalHigh!.toStringAsFixed(2)}; q=${f.q!.toStringAsFixed(3)}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ...f.limitations.map(
                          (l) => pw.Text(
                            '- $l',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
        if (snapshot.findings.any((f) => f.points.isEmpty))
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 16),
                pw.Text(
                  'Still collecting data',
                  style: pw.TextStyle(
                    font: display,
                    fontSize: 16,
                    color: accent,
                  ),
                ),
                pw.SizedBox(height: 6),
                for (final f in snapshot.findings.where(
                  (f) => f.points.isEmpty,
                ))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Text(
                      '${f.category.label}: no supported observations in this period.',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Changes & personal experiments',
          style: pw.TextStyle(font: display, fontSize: 18),
        ),
        if (snapshot.events.isEmpty && snapshot.experiments.isEmpty)
          pw.Text('No changes or personal experiments recorded.'),
        ...snapshot.events.map(
          (e) =>
              pw.Text('${e['at'].toString().substring(0, 10)} / ${e['title']}'),
        ),
        ...snapshot.experiments.map(
          (e) => pw.Text(
            '${e['title']} / ${e['status']} / target ${e['target']} ${e['unit']}\n${e['protocol']}\n${_experimentSummary(e)}',
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Next steps', style: pw.TextStyle(font: display, fontSize: 18)),
        pw.Text(
          'Keep logging comparable sessions and daily context. Choose one optional change at a time. Review incomplete categories before drawing conclusions about supplements or diet.',
        ),
        pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 18),
              pw.Text(
                'Methods & sources',
                style: pw.TextStyle(font: display, fontSize: 18),
              ),
              pw.Text(
                'Methods reviewed 2026-10-16. Descriptive comparisons require at least 3 days in each half; exploratory associations require 8 weekly blocks, detrending, 999 permutations and Benjamini-Hochberg correction. These are product screening thresholds, not proof of individual treatment effects.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              ...labsSources.entries.map(
                (e) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    '${e.key}\n${e.value}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      maxPages: 500,
    ),
  );
  return doc.save();
}

double _chartDay(DateTime day, DateTime origin) =>
    DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(origin.year, origin.month, origin.day))
        .inDays
        .toDouble();
