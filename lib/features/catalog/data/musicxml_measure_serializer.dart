import 'package:piano_exercises/features/catalog/data/musicxml_note_serializer.dart';
import 'package:piano_exercises/features/catalog/data/musicxml_voice_serializer.dart';
import 'package:piano_exercises/shared/music/music.dart';
import 'package:xml/xml.dart';

/// Mutable MusicXML attribute state carried across consecutive `<measure>` elements.
final class MusicXmlWriteContext {
  MusicXmlWriteContext({
    required this.activeKey,
    required this.activeTime,
    required this.initialScale,
    this.initialTempo,
  });

  KeySignature activeKey;
  TimeSignature activeTime;
  final Scale initialScale;
  final TempoMark? initialTempo;
  int? prevDivisions;
}

/// Writes one `<measure>` element for [measure] and advances [ctx].
void writeMusicXmlMeasure(
  XmlBuilder builder,
  ScoreMeasure measure, {
  required int measureIndex,
  required MusicXmlWriteContext ctx,
}) {
  final isFirst = measureIndex == 0;
  final effectiveTime = measure.timeSignature ?? ctx.activeTime;
  final keyChanged =
      !isFirst &&
      measure.keySignature != null &&
      measure.keySignature != ctx.activeKey;
  final timeChanged =
      !isFirst &&
      measure.timeSignature != null &&
      measure.timeSignature != ctx.activeTime;
  final effectiveKey = measure.keySignature ?? ctx.activeKey;
  ctx.activeKey = effectiveKey;
  ctx.activeTime = effectiveTime;

  final divisions = computeMusicXmlMeasureDivisions(measure, effectiveTime);
  final divisionsChanged = !isFirst && ctx.prevDivisions != divisions;
  ctx.prevDivisions = divisions;

  final measureBeats = resolveMusicXmlMeasureBeats(measure, effectiveTime);
  final measureTicks = musicXmlBeatsToTicks(measureBeats, divisions);
  final tempo = isFirst
      ? (measure.tempoMark ?? ctx.initialTempo)
      : measure.tempoMark;

  builder.element(
    'measure',
    attributes: <String, String>{'number': '${measure.measureNumber}'},
    nest: () {
      if (isFirst || divisionsChanged || keyChanged || timeChanged) {
        _writeAttributes(
          builder,
          _AttributesSpec(
            isFirst: isFirst,
            divisions: isFirst || divisionsChanged ? divisions : null,
            keyToWrite: (isFirst || keyChanged) ? effectiveKey : null,
            modeToWrite: isFirst ? ctx.initialScale.mode : null,
            timeToWrite: (isFirst || timeChanged) ? effectiveTime : null,
          ),
        );
      }
      if (tempo != null) {
        _writeTempoDirection(builder, tempo);
      }
      final staffSpec = _StaffWriteSpec(
        measure: measure,
        divisions: divisions,
        measureBeats: measureBeats,
        measureTicks: measureTicks,
      );
      _writeStaff(builder, staffSpec, staff: 1, emitTrailingBackup: true);
      _writeStaff(builder, staffSpec, staff: 2, emitTrailingBackup: false);
    },
  );
}

void _writeAttributes(XmlBuilder builder, _AttributesSpec spec) {
  builder.element(
    'attributes',
    nest: () {
      if (spec.divisions != null) {
        builder.element(
          'divisions',
          nest: () => builder.text('${spec.divisions}'),
        );
      }
      if (spec.keyToWrite != null) {
        builder.element(
          'key',
          nest: () {
            builder.element(
              'fifths',
              nest: () => builder.text('${spec.keyToWrite!.fifths}'),
            );
            if (spec.modeToWrite != null) {
              builder.element(
                'mode',
                nest: () => builder.text(spec.modeToWrite!.name),
              );
            }
          },
        );
      }
      if (spec.timeToWrite != null) {
        builder.element(
          'time',
          nest: () {
            builder.element(
              'beats',
              nest: () => builder.text('${spec.timeToWrite!.beats}'),
            );
            builder.element(
              'beat-type',
              nest: () => builder.text('${spec.timeToWrite!.beatType}'),
            );
          },
        );
      }
      if (spec.isFirst) {
        builder.element('staves', nest: () => builder.text('2'));
        builder.element(
          'clef',
          attributes: const <String, String>{'number': '1'},
          nest: () {
            builder.element('sign', nest: () => builder.text('G'));
            builder.element('line', nest: () => builder.text('2'));
          },
        );
        builder.element(
          'clef',
          attributes: const <String, String>{'number': '2'},
          nest: () {
            builder.element('sign', nest: () => builder.text('F'));
            builder.element('line', nest: () => builder.text('4'));
          },
        );
      }
    },
  );
}

void _writeTempoDirection(XmlBuilder builder, TempoMark tempo) {
  builder.element(
    'direction',
    nest: () {
      builder.element(
        'sound',
        attributes: <String, String>{'tempo': '${tempo.bpm}'},
      );
    },
  );
}

void _writeStaff(
  XmlBuilder builder,
  _StaffWriteSpec spec, {
  required int staff,
  required bool emitTrailingBackup,
}) {
  final notesByVoice = <int, List<TimedScoreNote>>{};
  final restsByVoice = <int, List<TimedRestEvent>>{};
  var noteCount = 0;

  for (final slice in spec.measure.slices) {
    final notes = staff == 1 ? slice.trebleNotes : slice.bassNotes;
    final rest = staff == 1 ? slice.trebleRest : slice.bassRest;
    for (final note in notes) {
      noteCount += 1;
      notesByVoice
          .putIfAbsent(note.voice, () => <TimedScoreNote>[])
          .add(TimedScoreNote(slice.beatOffset, note));
    }
    if (rest != null) {
      restsByVoice
          .putIfAbsent(rest.voice, () => <TimedRestEvent>[])
          .add(TimedRestEvent(slice.beatOffset, rest));
    }
  }

  if (noteCount == 0) {
    final fallbackVoice = restsByVoice.isNotEmpty
        ? restsByVoice.keys.first
        : (staff == 1 ? 1 : 2);
    writeMusicXmlMeasureRest(
      builder,
      durationTicks: spec.measureTicks,
      voice: fallbackVoice,
      staff: staff,
    );
    if (emitTrailingBackup && spec.measureTicks > 0) {
      writeMusicXmlBackup(builder, spec.measureTicks);
    }
    return;
  }

  final voices = notesByVoice.keys.toList()..sort();
  final assignedRests = <int, List<TimedRestEvent>>{
    for (final voice in voices) voice: <TimedRestEvent>[],
  };
  for (final entry in restsByVoice.entries) {
    final targetVoice = assignedRests.containsKey(entry.key)
        ? entry.key
        : voices.first;
    assignedRests[targetVoice]!.addAll(entry.value);
  }

  for (var i = 0; i < voices.length; i += 1) {
    final voice = voices[i];
    final hasMoreVoices = i + 1 < voices.length;
    final cursorTicks = writeMusicXmlVoiceStream(
      builder,
      MusicXmlVoiceStreamInput(
        notes: notesByVoice[voice]!,
        explicitRests: assignedRests[voice]!,
        staff: staff,
        voice: voice,
        isPrimaryVoice: i == 0,
        divisions: spec.divisions,
        measureBeats: spec.measureBeats,
      ),
    );
    if ((hasMoreVoices || emitTrailingBackup) && cursorTicks > 0) {
      writeMusicXmlBackup(builder, cursorTicks);
    }
  }
}

final class _AttributesSpec {
  const _AttributesSpec({
    required this.isFirst,
    required this.divisions,
    required this.keyToWrite,
    required this.modeToWrite,
    required this.timeToWrite,
  });

  final bool isFirst;
  final int? divisions;
  final KeySignature? keyToWrite;
  final ScaleMode? modeToWrite;
  final TimeSignature? timeToWrite;
}

final class _StaffWriteSpec {
  const _StaffWriteSpec({
    required this.measure,
    required this.divisions,
    required this.measureBeats,
    required this.measureTicks,
  });

  final ScoreMeasure measure;
  final int divisions;
  final RationalBeats measureBeats;
  final int measureTicks;
}
