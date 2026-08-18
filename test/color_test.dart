// ignore_for_file: avoid_print
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CupertinoDynamicColor material test', (WidgetTester tester) async {
    const c = CupertinoDynamicColor.withBrightness(
      color: Color(0xFFFFFFFF),
      darkColor: Color(0xFF000000),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Container(color: c),
      )
    );
    final container = tester.widget<Container>(find.byType(Container));
    final resolvedColor = container.color;
    print(resolvedColor);
    expect(resolvedColor?.toARGB32(), 0xFFFFFFFF);
  });
}
