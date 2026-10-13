import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:editors_pro/features/editor/widgets/audio_waveform_painter.dart';

void main() {
  group('AudioWaveformPainter', () {
    test('shouldRepaint returns true when peaks change', () {
      const painter1 = AudioWaveformPainter(
        peaks: [0.5, 0.8, 0.3],
        color: Colors.blue,
      );
      const painter2 = AudioWaveformPainter(
        peaks: [0.5, 0.8, 0.4],
        color: Colors.blue,
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when color changes', () {
      const painter1 = AudioWaveformPainter(
        peaks: [0.5, 0.8],
        color: Colors.blue,
      );
      const painter2 = AudioWaveformPainter(
        peaks: [0.5, 0.8],
        color: Colors.red,
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns true when rmsValues change', () {
      const painter1 = AudioWaveformPainter(
        peaks: [0.5, 0.8],
        color: Colors.blue,
        rmsValues: [0.3, 0.5],
      );
      const painter2 = AudioWaveformPainter(
        peaks: [0.5, 0.8],
        color: Colors.blue,
        rmsValues: [0.4, 0.5],
      );

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('shouldRepaint returns false when identical', () {
      const painter1 = AudioWaveformPainter(
        peaks: [0.5, 0.8],
        color: Colors.blue,
      );
      const painter2 = AudioWaveformPainter(
        peaks: [0.5, 0.8],
        color: Colors.blue,
      );

      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('paints without error on empty peaks', () {
      const painter = AudioWaveformPainter(
        peaks: [],
        color: Colors.blue,
      );

      // Should not throw
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(200, 50));
      recorder.endRecording().dispose();
    });

    test('paints without error with single peak', () {
      const painter = AudioWaveformPainter(
        peaks: [0.8],
        color: Colors.green,
      );

      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(100, 50));
      recorder.endRecording().dispose();
    });

    test('paints without error with many peaks', () {
      final peaks = List.generate(200, (i) => (i % 10) / 10.0);
      final painter = AudioWaveformPainter(
        peaks: peaks,
        color: Colors.purple,
      );

      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(400, 50));
      recorder.endRecording().dispose();
    });
  });

  group('AudioWaveformWidget', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AudioWaveformWidget(
              peaks: [0.5, 0.8, 0.3, 0.6],
              color: Colors.blue,
              width: 200,
              height: 50,
            ),
          ),
        ),
      );

      expect(find.byType(AudioWaveformWidget), findsOneWidget);
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('renders with rmsValues', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AudioWaveformWidget(
              peaks: [0.5, 0.8, 0.3, 0.6],
              rmsValues: [0.3, 0.5, 0.2, 0.4],
              color: Colors.orange,
              width: 200,
              height: 50,
            ),
          ),
        ),
      );

      expect(find.byType(AudioWaveformWidget), findsOneWidget);
    });
  });
}
