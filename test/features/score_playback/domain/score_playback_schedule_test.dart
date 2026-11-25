import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/score_playback/score_playback.dart';
import 'package:piano_exercises/shared/music/music.dart';

Score _buildTestScore() {
  final quarter = DurationValue(base: NoteBaseDuration.quarter);
  final half = DurationValue(base: NoteBaseDuration.half);
  return ScoreTimelineReducer.reduce(
    title: 'Test Study',
    initialTempo: TempoMark(120),
    measures: <MeasureTimelineInput>[
      MeasureTimelineInput(
        measureNumber: 1,
        notes: <NoteTimelineInput>[
          // Repeated C4 on beats 0 and 1, then tied E4 starting on beat 2 (half note -> bar 2).
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.c,
            octave: 4,
            beatOffset: const RationalBeats.zero(),
            duration: quarter,
          ),
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.c,
            octave: 4,
            beatOffset: RationalBeats(1),
            duration: quarter,
          ),
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.e,
            octave: 4,
            beatOffset: RationalBeats(2),
            duration: half,
            tie: TieType.start,
          ),
          // Bass whole-bar accompaniment G2 on beat 0.
          NoteTimelineInput(
            clef: Clef.bass,
            diatonicNote: DiatonicNote.g,
            octave: 2,
            beatOffset: const RationalBeats.zero(),
            duration: DurationValue(base: NoteBaseDuration.whole),
          ),
        ],
        rests: const <RestTimelineInput>[],
      ),
      MeasureTimelineInput(
        measureNumber: 2,
        tempoMark: TempoMark(60),
        notes: <NoteTimelineInput>[
          // Tied E4 stop for 1 quarter beat at 60 BPM (1000ms).
          NoteTimelineInput(
            clef: Clef.treble,
            diatonicNote: DiatonicNote.e,
            octave: 4,
            beatOffset: const RationalBeats.zero(),
            duration: quarter,
            tie: TieType.stop,
          ),
        ],
        rests: <RestTimelineInput>[
          RestTimelineInput(
            clef: Clef.treble,
            beatOffset: RationalBeats(1),
            duration: DurationValue(base: NoteBaseDuration.half, dots: 1),
          ),
        ],
      ),
      MeasureTimelineInput(
        measureNumber: 3,
        notes: const <NoteTimelineInput>[],
        rests: <RestTimelineInput>[
          RestTimelineInput(
            clef: Clef.treble,
            beatOffset: const RationalBeats.zero(),
            duration: DurationValue(base: NoteBaseDuration.whole),
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('PlaybackOutputMode', () {
    test(
      'resolves Auto/Piano/Speaker targets and cycles deterministically',
      () {
        expect(
          PlaybackOutputMode.auto.resolveTarget(hasConnectedMidi: false),
          PlaybackTarget.deviceAudio,
        );
        expect(
          PlaybackOutputMode.auto.resolveTarget(hasConnectedMidi: true),
          PlaybackTarget.midiPiano,
        );
        expect(
          PlaybackOutputMode.piano.resolveTarget(hasConnectedMidi: false),
          PlaybackTarget.midiPiano,
        );
        expect(
          PlaybackOutputMode.device.resolveTarget(hasConnectedMidi: true),
          PlaybackTarget.deviceAudio,
        );

        final second = PlaybackOutputMode.auto.nextMode();
        final third = second.nextMode();
        expect(second, PlaybackOutputMode.device);
        expect(third, PlaybackOutputMode.piano);
        expect(third.nextMode(), PlaybackOutputMode.auto);
      },
    );
  });

  group('ScorePlaybackSchedule', () {
    test('merges cross-bar ties, articulates repeated pitches, and honors tempo changes', () {
      final score = _buildTestScore();
      final schedule = ScorePlaybackSchedule.fromScore(score);

      expect(schedule.hasAudibleNotes, isTrue);
      expect(schedule.initialBpm, 120);
      // 4 audible spans: G2 (bar 1), C4 #1, C4 #2, and single tied E4 across bar 1->2.
      expect(schedule.notes, hasLength(4));

      final c4Spans = schedule.notes
          .where((n) => n.midiNote.number == 60)
          .toList();
      expect(c4Spans, hasLength(2));
      expect(c4Spans[0].startMs, 0);
      expect(c4Spans[1].startMs, 500);
      // First C4 releases cleanly before second C4 attacks at 500ms.
      expect(c4Spans[0].endMs, lessThan(c4Spans[1].startMs));

      // Tied E4 starts at beat 2 of bar 1 (1000ms), spans 2 beats @ 120 BPM (1000ms)
      // + 1 beat @ 60 BPM (1000ms) = ends at 3000ms without re-attacking!
      final e4Spans = schedule.notes
          .where((n) => n.midiNote.number == 64)
          .toList();
      expect(e4Spans, hasLength(1));
      expect(e4Spans.single.startMs, 1000);
      expect(e4Spans.single.endMs, 3000);
    });

    test('supports hand filtering, trailing empty-measure trimming, and mid-tie start', () {
      final score = _buildTestScore();

      // Left-hand only keeps only G2 (MIDI 43).
      final lhOnly = ScorePlaybackSchedule.fromScore(
        score,
        options: const ScorePlaybackOptions(
          includeTreble: false,
          includeBass: true,
        ),
      );
      expect(lhOnly.notes.map((n) => n.midiNote.number).toList(), <int>[43]);

      // Trimming trailing empty measure drops bar 3 (which has only rests).
      final trimmed = ScorePlaybackSchedule.fromScore(
        score,
        options: const ScorePlaybackOptions(trimTrailingEmptyMeasures: true),
      );
      expect(trimmed.sliceWindows.every((w) => w.measureNumber <= 2), isTrue);

      // Starting mid-piece on bar 2 (where E4 is TieType.stop) does not attack orphan stop.
      final midTie = ScorePlaybackSchedule.fromScore(
        score,
        options: const ScorePlaybackOptions(startMeasureIndex: 1),
      );
      expect(midTie.hasAudibleNotes, isFalse);

      // Binary search sliceAtMs locates slice windows accurately.
      expect(trimmed.sliceAtMs(0)?.sliceOrdinal, 0);
      expect(trimmed.sliceAtMs(550)?.sliceOrdinal, 1);
      expect(trimmed.sliceAtMs(2200)?.measureNumber, 2);
    });

    test(
      'clamps ultra-fast (<15ms) repeated pitches and sanitizes NaN tempoScale',
      () {
        final sixtyFourth = DurationValue(base: NoteBaseDuration.sixtyFourth);
        final fastScore = ScoreTimelineReducer.reduce(
          title: 'Rapid Trill',
          initialTempo: TempoMark(500), // 120ms quarter -> 7.5ms per 64th note!
          measures: <MeasureTimelineInput>[
            MeasureTimelineInput(
              measureNumber: 1,
              notes: <NoteTimelineInput>[
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 5,
                  beatOffset: const RationalBeats.zero(),
                  duration: sixtyFourth,
                ),
                NoteTimelineInput(
                  clef: Clef.treble,
                  diatonicNote: DiatonicNote.c,
                  octave: 5,
                  beatOffset: sixtyFourth.quarterBeats,
                  duration: sixtyFourth,
                ),
              ],
              rests: const <RestTimelineInput>[],
            ),
          ],
        );

        final schedule = ScorePlaybackSchedule.fromScore(
          fastScore,
          options: const ScorePlaybackOptions(tempoScale: double.nan),
        );
        expect(schedule.notes, hasLength(2));
        expect(schedule.notes[0].endMs, lessThan(schedule.notes[1].startMs));
      },
    );
  });
}
