import 'package:editors_pro/features/editor/widgets/text_overlay_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text selection only draws geometry, never a second text layer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 400,
      height: 200,
      child: Stack(children: [
        TextOverlayHandle(
          data: const TextOverlayData(
              clipId: 'title', text: 'Actual native text', isSelected: true),
          onPositionChanged: (_, __, ___) {},
        )
      ]),
    ))));
    expect(tester.takeException(), isNull);
    expect(find.text('Actual native text'), findsNothing);
  });

  testWidgets('drag commits its final position without snapping to stale props',
      (tester) async {
    final positions = <Offset>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 400,
      height: 200,
      child: Stack(children: [
        TextOverlayHandle(
          data: const TextOverlayData(
              clipId: 'title', text: 'Move', isSelected: true),
          onPositionChanged: (_, x, y) => positions.add(Offset(x, y)),
        )
      ]),
    ))));
    await tester.drag(find.byType(TextOverlayHandle), const Offset(80, 20));
    expect(positions, isNotEmpty);
    expect(positions.last.dx, greaterThan(0.6));
    expect(positions.last.dy, greaterThan(0.5));
  });
}
