const List<String> _pitchClasses = <String>[
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Formats a MIDI [noteNumber] (`0..127`) as scientific pitch notation (e.g. `60 -> C4`).
String formatMidiNoteName(int noteNumber) {
  RangeError.checkValueInInterval(noteNumber, 0, 127, 'noteNumber');
  final pitchClass = _pitchClasses[noteNumber % 12];
  final octave = (noteNumber ~/ 12) - 1;
  return '$pitchClass$octave';
}

/// Normalized MIDI Note On/Off event emitted by a connected MIDI device.
final class MidiNoteEvent {
  const MidiNoteEvent({
    required this.noteNumber,
    required this.velocity,
    required this.isNoteOn,
    required this.channel,
    required this.deviceId,
    required this.timestampMs,
  }) : assert(noteNumber >= 0 && noteNumber <= 127),
       assert(velocity >= 0 && velocity <= 127),
       assert(channel >= 0 && channel <= 15);

  /// Validates MIDI ranges and normalizes Note On with `velocity == 0` as Note Off.
  ///
  /// Throws [RangeError] if [noteNumber] (`0..127`), [velocity] (`0..127`), or
  /// [channel] (`0..15`) is out of range.
  factory MidiNoteEvent.fromChannelMessage({
    required int noteNumber,
    required int velocity,
    required bool isNoteOn,
    required int channel,
    required String deviceId,
    required int timestampMs,
  }) {
    RangeError.checkValueInInterval(noteNumber, 0, 127, 'noteNumber');
    RangeError.checkValueInInterval(velocity, 0, 127, 'velocity');
    RangeError.checkValueInInterval(channel, 0, 15, 'channel');
    return MidiNoteEvent(
      noteNumber: noteNumber,
      velocity: velocity,
      // MIDI keyboards commonly encode Note Off via Note On with velocity 0.
      isNoteOn: isNoteOn && velocity > 0,
      channel: channel,
      deviceId: deviceId,
      timestampMs: timestampMs,
    );
  }

  /// Non-throwing variant of [MidiNoteEvent.fromChannelMessage] for untrusted streams.
  static MidiNoteEvent? tryFromChannelMessage({
    required int noteNumber,
    required int velocity,
    required bool isNoteOn,
    required int channel,
    required String deviceId,
    required int timestampMs,
  }) {
    if (noteNumber < 0 ||
        noteNumber > 127 ||
        velocity < 0 ||
        velocity > 127 ||
        channel < 0 ||
        channel > 15) {
      return null;
    }
    return MidiNoteEvent(
      noteNumber: noteNumber,
      velocity: velocity,
      isNoteOn: isNoteOn && velocity > 0,
      channel: channel,
      deviceId: deviceId,
      timestampMs: timestampMs,
    );
  }

  final int noteNumber;
  final int velocity;
  final bool isNoteOn;
  final int channel;
  final String deviceId;
  final int timestampMs;

  String get noteName => formatMidiNoteName(noteNumber);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MidiNoteEvent &&
            other.noteNumber == noteNumber &&
            other.velocity == velocity &&
            other.isNoteOn == isNoteOn &&
            other.channel == channel &&
            other.deviceId == deviceId &&
            other.timestampMs == timestampMs);
  }

  @override
  int get hashCode => Object.hash(
    noteNumber,
    velocity,
    isNoteOn,
    channel,
    deviceId,
    timestampMs,
  );
}
