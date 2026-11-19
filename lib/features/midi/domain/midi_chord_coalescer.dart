import 'dart:async';

import 'package:piano_exercises/features/midi/domain/midi_device_info.dart';
import 'package:piano_exercises/features/midi/domain/midi_note_event.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Immutable snapshot of notes flushed after a MIDI chord coalescing window.
final class MidiChordFlush {
  MidiChordFlush({
    required Set<MidiNote> batchNotes,
    required Set<MidiNote> combinedNotes,
    required this.startedAtMs,
  }) : batchNotes = Set<MidiNote>.unmodifiable(batchNotes),
       combinedNotes = Set<MidiNote>.unmodifiable(combinedNotes);

  /// Notes captured during the coalescing window (including staccato releases).
  final Set<MidiNote> batchNotes;

  /// Union of currently held prompt notes and [batchNotes].
  final Set<MidiNote> combinedNotes;

  /// Timestamp (`clockMs`) when the coalescing batch began.
  final int startedAtMs;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MidiChordFlush &&
            other.startedAtMs == startedAtMs &&
            _setEquals(other.batchNotes, batchNotes) &&
            _setEquals(other.combinedNotes, combinedNotes));
  }

  @override
  int get hashCode => Object.hash(
    startedAtMs,
    Object.hashAllUnordered(batchNotes),
    Object.hashAllUnordered(combinedNotes),
  );
}

/// Coalesces near-simultaneous Note On events and tracks per-device held keys.
final class MidiChordCoalescer {
  MidiChordCoalescer({
    required this._chordWindow,
    required this._clockMs,
    required this._onFlush,
  });

  final Duration _chordWindow;
  final int Function() _clockMs;
  final void Function(MidiChordFlush flush) _onFlush;

  final Set<MidiNote> _activeHeldNotes = <MidiNote>{};
  final Set<MidiNote> _carryoverHeldNotes = <MidiNote>{};
  final Map<String, Set<MidiNote>> _heldByDevice = <String, Set<MidiNote>>{};
  final Set<String> _knownConnectedDeviceIds = <String>{};
  final Set<MidiNote> _pendingBatchNotes = <MidiNote>{};

  int? _pendingAttemptStartedAtMs;
  Timer? _coalesceTimer;
  bool _isPaused = false;
  bool _isDisposed = false;

  bool get isPaused => _isPaused;

  /// Pauses or resumes evaluation while preserving held-key carryover state.
  void setPaused(bool paused) {
    if (_isDisposed || paused == _isPaused) {
      return;
    }
    if (paused) {
      _isPaused = true;
      _cancelPendingAttempt();
      _carryoverHeldNotes.addAll(_activeHeldNotes);
      _activeHeldNotes.clear();
      return;
    }
    _isPaused = false;
    _activeHeldNotes.clear();
    for (final held in _heldByDevice.values) {
      _carryoverHeldNotes.addAll(held);
    }
  }

  /// Moves currently held keys into carryover so legato holds do not fire on the next prompt.
  void resetActivePrompt() {
    if (_isDisposed) {
      return;
    }
    _cancelPendingAttempt();
    _carryoverHeldNotes.addAll(_activeHeldNotes);
    _activeHeldNotes.clear();
  }

  /// Records a Note On/Off event and schedules or flushes chord evaluation.
  void onNoteEvent(MidiNoteEvent event) {
    if (_isDisposed) {
      return;
    }
    final note = event.note;
    if (event.isNoteOn) {
      _heldByDevice.putIfAbsent(event.deviceId, () => <MidiNote>{}).add(note);
      if (_isPaused) {
        _carryoverHeldNotes.add(note);
        return;
      }
      _carryoverHeldNotes.remove(note);
      _activeHeldNotes.add(note);
      _enqueueOrStartBatch(note);
      return;
    }

    final deviceHeld = _heldByDevice[event.deviceId];
    deviceHeld?.remove(note);
    if (deviceHeld != null && deviceHeld.isEmpty) {
      _heldByDevice.remove(event.deviceId);
    }
    final stillHeldElsewhere = _heldByDevice.values.any(
      (held) => held.contains(note),
    );
    if (!stillHeldElsewhere) {
      _activeHeldNotes.remove(note);
      _carryoverHeldNotes.remove(note);
    }
  }

  /// Releases held notes belonging to devices that are no longer connected.
  void syncConnectedDevices(List<MidiDeviceInfo> devices) {
    if (_isDisposed) {
      return;
    }
    final connectedIds = <String>{};
    final explicitlyDisconnectedIds = <String>{};
    for (final device in devices) {
      if (device.isConnected) {
        connectedIds.add(device.id);
      } else {
        explicitlyDisconnectedIds.add(device.id);
      }
    }

    final disconnectedIds = <String>{
      ...explicitlyDisconnectedIds,
      for (final knownId in _knownConnectedDeviceIds)
        if (!connectedIds.contains(knownId)) knownId,
    };

    _knownConnectedDeviceIds
      ..clear()
      ..addAll(connectedIds);

    for (final deviceId in disconnectedIds) {
      _releaseDeviceHeldNotes(deviceId);
    }
  }

  /// Cancels any pending window timer without triggering [onFlush].
  void dispose() {
    _isDisposed = true;
    _cancelPendingAttempt();
    _activeHeldNotes.clear();
    _carryoverHeldNotes.clear();
    _heldByDevice.clear();
    _knownConnectedDeviceIds.clear();
  }

  void _enqueueOrStartBatch(MidiNote note) {
    if (_coalesceTimer != null) {
      _pendingBatchNotes.add(note);
      return;
    }
    _pendingAttemptStartedAtMs = _clockMs();
    _pendingBatchNotes
      ..clear()
      ..addAll(_activeHeldNotes);
    if (_chordWindow <= Duration.zero) {
      _flushPendingAttempt();
    } else {
      _coalesceTimer = Timer(_chordWindow, _flushPendingAttempt);
    }
  }

  void _flushPendingAttempt() {
    _coalesceTimer = null;
    if (_isDisposed || _isPaused || _pendingBatchNotes.isEmpty) {
      _pendingAttemptStartedAtMs = null;
      _pendingBatchNotes.clear();
      return;
    }

    final startedAtMs = _pendingAttemptStartedAtMs ?? _clockMs();
    final batchNotes = Set<MidiNote>.unmodifiable(_pendingBatchNotes);
    final combinedNotes = Set<MidiNote>.unmodifiable(<MidiNote>{
      ..._activeHeldNotes,
      ...batchNotes,
    });
    _pendingBatchNotes.clear();
    _pendingAttemptStartedAtMs = null;

    _onFlush(
      MidiChordFlush(
        batchNotes: batchNotes,
        combinedNotes: combinedNotes,
        startedAtMs: startedAtMs,
      ),
    );
  }

  void _releaseDeviceHeldNotes(String deviceId) {
    final removed = _heldByDevice.remove(deviceId);
    if (removed == null || removed.isEmpty) {
      return;
    }
    final stillHeldElsewhere = <MidiNote>{
      for (final held in _heldByDevice.values) ...held,
    };
    for (final note in removed) {
      if (!stillHeldElsewhere.contains(note)) {
        _activeHeldNotes.remove(note);
        _carryoverHeldNotes.remove(note);
      }
    }
  }

  void _cancelPendingAttempt() {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _pendingBatchNotes.clear();
    _pendingAttemptStartedAtMs = null;
  }
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) {
    return true;
  }
  return a.length == b.length && a.containsAll(b);
}
