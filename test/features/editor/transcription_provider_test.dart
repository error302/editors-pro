import 'package:editors_pro/features/editor/providers/transcription_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TranscriptionStatus', () {
    test('has correct labels', () {
      expect(TranscriptionStatus.idle.label, 'Idle');
      expect(TranscriptionStatus.loadingModel.label, 'Loading model…');
      expect(TranscriptionStatus.extractingAudio.label, 'Extracting audio…');
      expect(TranscriptionStatus.transcribing.label, 'Transcribing…');
      expect(
        TranscriptionStatus.processingSegments.label,
        'Processing segments…',
      );
      expect(TranscriptionStatus.complete.label, 'Complete');
      expect(TranscriptionStatus.error.label, 'Error');
    });

    test('has correct progressStart values', () {
      expect(TranscriptionStatus.idle.progressStart, 0.0);
      expect(TranscriptionStatus.loadingModel.progressStart, 0.0);
      expect(TranscriptionStatus.extractingAudio.progressStart, 0.1);
      expect(TranscriptionStatus.transcribing.progressStart, 0.3);
      expect(TranscriptionStatus.processingSegments.progressStart, 0.85);
      expect(TranscriptionStatus.complete.progressStart, 1.0);
      expect(TranscriptionStatus.error.progressStart, 0.0);
    });
  });

  group('TranscriptionSegmentData', () {
    TranscriptionSegmentData makeSegment({
      int startMs = 5000,
      int endMs = 9000,
      double confidence = 0.9,
      bool selected = true,
    }) {
      return TranscriptionSegmentData(
        id: 'seg-1',
        text: 'Hello world',
        startMs: startMs,
        endMs: endMs,
        confidence: confidence,
        selected: selected,
      );
    }

    test('startTimeFormatted formats correctly', () {
      final seg = makeSegment(startMs: 65000); // 1:05
      expect(seg.startTimeFormatted, '1:05');
    });

    test('startTimeFormatted zero', () {
      final seg = makeSegment(startMs: 0);
      expect(seg.startTimeFormatted, '0:00');
    });

    test('endTimeFormatted formats correctly', () {
      final seg = makeSegment(endMs: 125000); // 2:05
      expect(seg.endTimeFormatted, '2:05');
    });

    test('durationFormatted under a minute', () {
      final seg = makeSegment(startMs: 0, endMs: 4000);
      expect(seg.durationFormatted, '4s');
    });

    test('durationFormatted over a minute', () {
      final seg = makeSegment(startMs: 0, endMs: 90000); // 1:30
      expect(seg.durationFormatted, '1:30');
    });

    test('confidenceLabel high', () {
      final seg = makeSegment(confidence: 0.95);
      expect(seg.confidenceLabel, 'High');
    });

    test('confidenceLabel medium', () {
      final seg = makeSegment(confidence: 0.65);
      expect(seg.confidenceLabel, 'Medium');
    });

    test('confidenceLabel low', () {
      final seg = makeSegment(confidence: 0.3);
      expect(seg.confidenceLabel, 'Low');
    });

    test('copyWith overrides specified fields', () {
      final seg = makeSegment();
      final updated = seg.copyWith(text: 'Updated', selected: false);
      expect(updated.text, 'Updated');
      expect(updated.selected, isFalse);
      expect(updated.id, seg.id); // unchanged
    });
  });

  group('TranscriptionState', () {
    test('has expected defaults', () {
      const state = TranscriptionState();
      expect(state.isTranscribing, isFalse);
      expect(state.progress, 0.0);
      expect(state.status, TranscriptionStatus.idle);
      expect(state.segments, isEmpty);
      expect(state.errorMessage, isNull);
      expect(state.selectedLanguage, 'auto');
      expect(state.selectedModel, 'base');
    });

    test('hasSegments is true when segments exist', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'Hello',
            startMs: 0,
            endMs: 1000,
            confidence: 0.9,
          ),
        ],
      );
      expect(state.hasSegments, isTrue);
    });

    test('allSelected is true when all segments are selected', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'A',
            startMs: 0,
            endMs: 1000,
            confidence: 0.9,
            selected: true,
          ),
          TranscriptionSegmentData(
            id: '2',
            text: 'B',
            startMs: 1000,
            endMs: 2000,
            confidence: 0.8,
            selected: true,
          ),
        ],
      );
      expect(state.allSelected, isTrue);
    });

    test('noneSelected is true when no segments are selected', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'A',
            startMs: 0,
            endMs: 1000,
            confidence: 0.9,
            selected: false,
          ),
          TranscriptionSegmentData(
            id: '2',
            text: 'B',
            startMs: 1000,
            endMs: 2000,
            confidence: 0.8,
            selected: false,
          ),
        ],
      );
      expect(state.noneSelected, isTrue);
    });

    test('selectedCount works correctly', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'A',
            startMs: 0,
            endMs: 1000,
            confidence: 0.9,
            selected: true,
          ),
          TranscriptionSegmentData(
            id: '2',
            text: 'B',
            startMs: 1000,
            endMs: 2000,
            confidence: 0.8,
            selected: false,
          ),
          TranscriptionSegmentData(
            id: '3',
            text: 'C',
            startMs: 2000,
            endMs: 3000,
            confidence: 0.7,
            selected: true,
          ),
        ],
      );
      expect(state.selectedCount, 2);
    });

    test('selectedSegments filters correctly', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'A',
            startMs: 0,
            endMs: 1000,
            confidence: 0.9,
            selected: true,
          ),
          TranscriptionSegmentData(
            id: '2',
            text: 'B',
            startMs: 1000,
            endMs: 2000,
            confidence: 0.8,
            selected: false,
          ),
        ],
      );
      expect(state.selectedSegments.length, 1);
      expect(state.selectedSegments.first.id, '1');
    });

    test('toSrt generates valid SRT output', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'Hello world',
            startMs: 0,
            endMs: 3000,
            confidence: 0.9,
          ),
          TranscriptionSegmentData(
            id: '2',
            text: 'Goodbye',
            startMs: 4000,
            endMs: 7000,
            confidence: 0.8,
            selected: false,
          ),
        ],
      );
      final srt = state.toSrt();
      // Only selected segments (segment 1) should appear
      expect(srt, contains('Hello world'));
      expect(srt, contains('00:00:00,000'));
      expect(srt, contains('00:00:03,000'));
      expect(srt, isNot(contains('Goodbye')));
    });

    test('toVtt generates valid VTT output', () {
      const state = TranscriptionState(
        segments: [
          TranscriptionSegmentData(
            id: '1',
            text: 'Test subtitle',
            startMs: 1000,
            endMs: 4000,
            confidence: 0.95,
          ),
        ],
      );
      final vtt = state.toVtt();
      expect(vtt, startsWith('WEBVTT'));
      expect(vtt, contains('Test subtitle'));
      expect(vtt, contains('00:00:01.000'));
      expect(vtt, contains('00:00:04.000'));
    });

    test('copyWith updates only specified fields', () {
      const state = TranscriptionState();
      final updated = state.copyWith(
        isTranscribing: true,
        progress: 0.5,
        status: TranscriptionStatus.transcribing,
      );
      expect(updated.isTranscribing, isTrue);
      expect(updated.progress, 0.5);
      expect(updated.status, TranscriptionStatus.transcribing);
      expect(updated.segments, isEmpty);
      expect(updated.selectedLanguage, 'auto');
    });

    test('copyWith clearError clears the error', () {
      const state = TranscriptionState(errorMessage: 'Test error');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
    });

    test('copyWith does not clear error without clearError flag', () {
      const state = TranscriptionState(errorMessage: 'Test error');
      final updated = state.copyWith(progress: 0.5);
      expect(updated.errorMessage, 'Test error');
    });
  });
}
