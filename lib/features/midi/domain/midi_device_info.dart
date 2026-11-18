/// Immutable descriptor for a discovered or connected MIDI device.
final class MidiDeviceInfo {
  const MidiDeviceInfo({
    required this.id,
    required this.name,
    required this.typeLabel,
    required this.isConnected,
    this.isConnecting = false,
  });

  final String id;
  final String name;
  final String typeLabel;
  final bool isConnected;
  final bool isConnecting;

  MidiDeviceInfo copyWith({
    String? id,
    String? name,
    String? typeLabel,
    bool? isConnected,
    bool? isConnecting,
  }) {
    return MidiDeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      typeLabel: typeLabel ?? this.typeLabel,
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MidiDeviceInfo &&
            other.id == id &&
            other.name == name &&
            other.typeLabel == typeLabel &&
            other.isConnected == isConnected &&
            other.isConnecting == isConnecting);
  }

  @override
  int get hashCode =>
      Object.hash(id, name, typeLabel, isConnected, isConnecting);
}
