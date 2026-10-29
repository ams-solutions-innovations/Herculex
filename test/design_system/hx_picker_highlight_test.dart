// Only the chosen picker row is tinted: a hovered or focused one (a mouse or
// keyboard on the phone, scrcpy, a tablet) must not read as a second choice.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/hx_picker.dart';
import 'package:herculex/design_system/theme/app_theme.dart';

Future<int> _pixel(WidgetTester t, GlobalKey key, Offset at) async {
  final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late int argb;
  await t.runAsync(() async {
    final img = await b.toImage();
    final data = (await img.toByteData())!;
    final x = at.dx.round(), y = at.dy.round();
    final i = (y * img.width + x) * 4;
    argb =
        (data.getUint8(i) << 16) |
        (data.getUint8(i + 1) << 8) |
        data.getUint8(i + 2);
    img.dispose();
  });
  return argb;
}

void main() {
  testWidgets('an unselected row paints no fill when hovered or focused', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => RepaintBoundary(key: key, child: child),
        home: Material(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHxPicker<int>(
                  context,
                  title: 'Pick',
                  selected: 0,
                  options: [
                    for (var i = 0; i < 4; i++)
                      HxPickerOption(value: i, label: 'Option $i'),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rest = Offset(300, tester.getCenter(find.text('Option 1')).dy);
    final last = Offset(300, tester.getCenter(find.text('Option 3')).dy);
    final before = await _pixel(tester, key, last);
    expect(before, await _pixel(tester, key, rest));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pumpAndSettle();
    expect(await _pixel(tester, key, last), before);
  });
}
