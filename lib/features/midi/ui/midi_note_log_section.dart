import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/state/midi_providers.dart';

/// Displays the live Note On/Off feed with a clear action.
class MidiNoteLogSection extends StatelessWidget {
  const MidiNoteLogSection({
    super.key,
    required this.entries,
    required this.onClear,
  });

  final List<MidiNoteLogEntry> entries;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Live Note Events (${entries.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: entries.isEmpty ? null : onClear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    'Play a key on a connected MIDI keyboard to see live Note On/Off events.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _NoteEventTile(entry: entries[index]),
                ),
        ),
      ],
    );
  }
}

class _NoteEventTile extends StatelessWidget {
  const _NoteEventTile({required this.entry});

  final MidiNoteLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final event = entry.event;
    final colorScheme = Theme.of(context).colorScheme;
    final badgeColor = event.isNoteOn
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final badgeTextColor = event.isNoteOn
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          event.isNoteOn ? 'ON' : 'OFF',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: badgeTextColor, fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(
        event.noteName,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        'MIDI ${event.noteNumber} · vel ${event.velocity} · ch ${event.channel + 1} · ${event.timestampMs} ms',
      ),
      trailing: Text(
        '#${entry.sequence}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
