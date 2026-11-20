import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/shared/music/music.dart';

void main() {
  const parser = MusicXmlScoreParser();
  const serializer = MusicXmlScoreSerializer();

  group('MusicXmlScoreSerializer round-trip', () {
    test('round-trips golden simplified and polyphonic fixtures cleanly', () {
      for (final path in const <String>[
        'test/fixtures/simplified_melody_bass.musicxml',
        'test/fixtures/polyphonic_grand_staff.musicxml',
      ]) {
        final raw = Uint8List.fromList(File(path).readAsBytesSync());
        final original = parser.parseBytes(raw, fileName: path).score;
        final xmlBytes = serializer.serialize(original);
        final roundTripped = parser
            .parseBytes(xmlBytes, fileName: 'out.musicxml')
            .score;

        expect(roundTripped.title, original.title);
        expect(roundTripped.artist, original.artist);
        expect(roundTripped.scale, original.scale);
        expect(roundTripped.timeSignature, original.timeSignature);
        expect(roundTripped.measures.length, original.measures.length);
        expect(roundTripped.slices.length, original.slices.length);
        for (var i = 0; i < original.slices.length; i += 1) {
          final origSlice = original.slices[i];
          final nextSlice = roundTripped.slices[i];
          expect(nextSlice.beatOffset, origSlice.beatOffset);
          expect(
            nextSlice.trebleNotes.map((n) => n.staffNote).toList(),
            origSlice.trebleNotes.map((n) => n.staffNote).toList(),
          );
          expect(
            nextSlice.bassNotes.map((n) => n.staffNote).toList(),
            origSlice.bassNotes.map((n) => n.staffNote).toList(),
          );
          expect(
            nextSlice.trebleNotes.map((n) => n.tie).toList(),
            origSlice.trebleNotes.map((n) => n.tie).toList(),
          );
          expect(
            nextSlice.trebleNotes.map((n) => n.showAccidental).toList(),
            origSlice.trebleNotes.map((n) => n.showAccidental).toList(),
          );
        }
      }
    });

    test('preserves sharp/flat key accidentals, explicit naturals, chords, cross-bar ties, and beams', () {
      final eighth = DurationValue(base: NoteBaseDuration.eighth);
      final quarter = DurationValue(base: NoteBaseDuration.quarter);
      final half = DurationValue(base: NoteBaseDuration.half);
      final score = ScoreTimelineReducer.reduce(
        title: 'Round Trip Study',
        artist: 'Clara Schumann',
        initialScale: Scale.fromKeySignature(
          const KeySignature(4), // E major: F#, C#, G#, D#
          mode: ScaleMode.major,
        ),
        initialTimeSignature: TimeSignature.common,
        initialTempo: TempoMark(112),
        measures: <MeasureTimelineInput>[
          MeasureTimelineInput(
            measureNumber: 1,
            tempoMark: TempoMark(112),
            notes: <NoteTimelineInput>[
              // Natural F4 in E major -> explicit <alter>0</alter> + <accidental>natural</accidental>
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.f,
                octave: 4,
                explicitAlter: 0,
                writtenAccidental: Accidental.natural,
                beatOffset: const RationalBeats.zero(),
                duration: quarter,
              ),
              // Chord at beat 1 (G#4 + B4)
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.g,
                octave: 4,
                explicitAlter: 1,
                beatOffset: RationalBeats(1),
                duration: quarter,
              ),
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.b,
                octave: 4,
                explicitAlter: 0,
                beatOffset: RationalBeats(1),
                duration: quarter,
              ),
              // Beamed eighths at beat 2..3
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.c,
                octave: 5,
                explicitAlter: 1,
                beatOffset: RationalBeats(2),
                duration: eighth,
                beamGroupId: 'b1',
              ),
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.d,
                octave: 5,
                explicitAlter: 1,
                beatOffset: RationalBeats(5, 2),
                duration: eighth,
                beamGroupId: 'b1',
              ),
              // Cross-bar tie start at beat 3
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.e,
                octave: 5,
                explicitAlter: 0,
                beatOffset: RationalBeats(3),
                duration: quarter,
                tie: TieType.start,
              ),
            ],
          ),
          MeasureTimelineInput(
            measureNumber: 2,
            keySignature: const KeySignature(-3), // Eb major modulation
            timeSignature: TimeSignature(3, 4),
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.e,
                octave: 5,
                explicitAlter: -1,
                beatOffset: const RationalBeats.zero(),
                duration: half,
                tie: TieType.continueTie,
              ),
            ],
          ),
          MeasureTimelineInput(
            measureNumber: 3,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.e,
                octave: 5,
                explicitAlter: -1,
                beatOffset: const RationalBeats.zero(),
                duration: quarter,
                tie: TieType.stop,
              ),
            ],
          ),
        ],
      );

      final bytes = serializer.serialize(score);
      final parsed = parser.parseBytes(bytes, fileName: 'study.musicxml');
      final out = parsed.score;

      expect(out.title, 'Round Trip Study');
      expect(out.artist, 'Clara Schumann');
      expect(out.scale, Scale.fromKeySignature(const KeySignature(4)));
      expect(out.initialTempo, TempoMark(112));
      expect(out.measures, hasLength(3));

      final m1 = out.measures[0];
      final f4 = m1.slices[0].trebleNotes.single;
      expect(f4.staffNote.accidental, Accidental.natural);
      expect(f4.showAccidental, isTrue);
      expect(m1.slices[1].trebleNotes, hasLength(2)); // G#4 + B4 chord
      expect(m1.slices[2].trebleNotes.single.beamGroupId, isNotNull);
      expect(
        m1.slices[3].trebleNotes.single.beamGroupId,
        m1.slices[2].trebleNotes.single.beamGroupId,
      );
      expect(m1.slices[4].trebleNotes.single.tie, TieType.start);

      final m2 = out.measures[1];
      expect(m2.keySignature, const KeySignature(-3));
      expect(m2.timeSignature, TimeSignature(3, 4));
      expect(m2.slices[0].trebleNotes.single.tie, TieType.continueTie);
      expect(
        m2.slices[0].trebleNotes.single.staffNote.accidental,
        Accidental.flat,
      );

      final m3 = out.measures[2];
      expect(m3.slices[0].trebleNotes.single.tie, TieType.stop);
    });

    test('round-trips polyphonic same-staff voices and full-bar rests in 3/4 and 4/4', () {
      final quarter = DurationValue(base: NoteBaseDuration.quarter);
      final half = DurationValue(base: NoteBaseDuration.half);
      final score = ScoreTimelineReducer.reduce(
        title: 'Voices And Rests',
        initialScale: Scale.fromKeySignature(const KeySignature(-2)),
        initialTimeSignature: TimeSignature(3, 4),
        measures: <MeasureTimelineInput>[
          // Empty 3/4 measure
          MeasureTimelineInput(measureNumber: 1),
          // Polyphonic voice 1 + voice 2 on treble, empty bass
          MeasureTimelineInput(
            measureNumber: 2,
            notes: <NoteTimelineInput>[
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.b,
                octave: 4,
                explicitAlter: -1,
                beatOffset: const RationalBeats.zero(),
                duration: half,
                voice: 1,
              ),
              NoteTimelineInput(
                clef: Clef.treble,
                diatonicNote: DiatonicNote.f,
                octave: 4,
                explicitAlter: 0,
                beatOffset: RationalBeats(1),
                duration: quarter,
                voice: 2,
              ),
            ],
          ),
          // Empty 4/4 measure
          MeasureTimelineInput(
            measureNumber: 3,
            timeSignature: TimeSignature.common,
          ),
        ],
      );

      final bytes = serializer.serialize(score);
      final roundTripped = parser
          .parseBytes(bytes, fileName: 'voices.musicxml')
          .score;

      expect(roundTripped.measures, hasLength(3));
      // Measure 1: full-bar rest in 3/4 = 3 quarter beats
      expect(roundTripped.measures[0].slices, hasLength(1));
      expect(
        roundTripped
            .measures[0]
            .slices
            .single
            .trebleRest
            ?.duration
            .quarterBeats,
        RationalBeats(3),
      );
      expect(
        roundTripped.measures[0].slices.single.bassRest?.duration.quarterBeats,
        RationalBeats(3),
      );

      // Measure 2: voice 1 B4 at beat 0, voice 2 F4 at beat 1
      expect(roundTripped.measures[1].slices[0].trebleNotes.single.voice, 1);
      expect(roundTripped.measures[1].slices[1].beatOffset, RationalBeats(1));
      expect(roundTripped.measures[1].slices[1].trebleNotes.single.voice, 2);

      // Measure 3: full-bar rest in 4/4 = 4 quarter beats
      expect(
        roundTripped
            .measures[2]
            .slices
            .single
            .trebleRest
            ?.duration
            .quarterBeats,
        RationalBeats(4),
      );
      expect(
        roundTripped.measures[2].slices.single.bassRest?.duration.quarterBeats,
        RationalBeats(4),
      );
    });
  });
}
