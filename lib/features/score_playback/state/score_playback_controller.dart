import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/score_playback/domain/pcm_audio_output.dart';
import 'package:piano_exercises/features/score_playback/domain/piano_pcm_synthesizer.dart';
import 'package:piano_exercises/features/score_playback/domain/playback_models.dart';
import 'package:piano_exercises/features/score_playback/domain/score_playback_schedule.dart';
import 'package:piano_exercises/features/score_playback/state/score_playback_state.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Orchestrates real-time MIDI hardware output, device PCM streaming, and score cursor updates.
class ScorePlaybackController extends Notifier<ScorePlaybackState> {
  ScorePlaybackController(this.arg);

  static const int _lookaheadMs = 420;
  static const int _chunkDurationMs = 200;

  final ScorePlaybackSessionId arg;

  late MidiOutputSink _midiSink;
  late PcmAudioOutput _pcmOutput;
  late PianoPcmSynthesizer _synthesizer;
  late int Function() _clockMs;
  late Duration _tickInterval;

  Timer? _tickTimer;
  ScorePlaybackSchedule? _schedule;
  PlaybackTarget? _runningTarget;
  List<String> _targetDeviceIds = const <String>[];
  final List<PlaybackNoteSpan> _soundingMidiNotes = <PlaybackNoteSpan>[];
  int _nextNoteCursor = 0;
  int _synthesizedSamples = 0;
  int _runStartClockMs = 0;
  int _tickCount = 0;
  bool _looping = false;

  @override
  ScorePlaybackState build() {
    _midiSink = ref.watch(midiOutputSinkProvider);
    _pcmOutput = ref.watch(pcmAudioOutputProvider);
    _synthesizer = ref.watch(pianoPcmSynthesizerProvider);
    _clockMs = ref.watch(scorePlaybackClockMsProvider);
    _tickInterval = ref.watch(scorePlaybackTickIntervalProvider);
    ref.onDispose(() => _haltPlayback(flushDeviceAudio: true));

    ref.listen<PlaybackOutputMode>(playbackOutputModeProvider, (prev, next) {
      if (prev != next && state.isPlaying) {
        stop();
      }
    });
    ref.listen<double>(playbackSpeedProvider, (prev, next) {
      if (prev != next && state.isPlaying) {
        stop();
      }
    });
    ref.listen<List<MidiDeviceInfo>>(connectedMidiDevicesProvider, (_, next) {
      if (state.isPlaying &&
          _runningTarget == PlaybackTarget.midiPiano &&
          next.isEmpty) {
        stop();
      }
    });
    return const ScorePlaybackState();
  }

  /// Starts playing [score] using [options] and the active output target.
  bool playScore(
    Score score, {
    ScorePlaybackOptions options = const ScorePlaybackOptions(),
    bool loop = false,
  }) {
    if (!ref.mounted) {
      return false;
    }
    stop();

    final mode = ref.read(playbackOutputModeProvider);
    final connectedDevices = ref.read(connectedMidiDevicesProvider);
    final hasMidi = connectedDevices.isNotEmpty;
    if (mode == PlaybackOutputMode.piano && !hasMidi) {
      return false;
    }
    final effectiveOptions = options.scaledBy(ref.read(playbackSpeedProvider));
    final schedule = ScorePlaybackSchedule.fromScore(
      score,
      options: effectiveOptions,
    );
    if (!schedule.hasAudibleNotes || schedule.sliceWindows.isEmpty) {
      return false;
    }

    final target = mode.resolveTarget(hasConnectedMidi: hasMidi);
    _schedule = schedule;
    _runningTarget = target;
    _targetDeviceIds = target == PlaybackTarget.midiPiano
        ? connectedDevices.map((d) => d.id).toList(growable: false)
        : const <String>[];
    _looping = loop;
    _soundingMidiNotes.clear();
    _nextNoteCursor = 0;
    _synthesizedSamples = 0;
    _runStartClockMs = _clockMs();
    _tickCount = 0;

    final firstWindow = schedule.sliceAtMs(0)!;
    state = ScorePlaybackState(
      isPlaying: true,
      activeTarget: target,
      activeSliceOrdinal: firstWindow.sliceOrdinal,
      activeSliceIndex: firstWindow.sliceIndex,
      activeMeasureNumber: firstWindow.measureNumber,
      bpm: (schedule.initialBpm * effectiveOptions.tempoScale).round(),
      isLooping: loop,
    );

    _advanceOutputsAt(0);
    _tickTimer = Timer.periodic(_tickInterval, (_) => _onTick());
    return true;
  }

  /// Immediately stops active playback and silences MIDI/speaker outputs.
  void stop() {
    _haltPlayback(flushDeviceAudio: true);
    if (ref.mounted && state.isPlaying) {
      state = const ScorePlaybackState();
    }
  }

  void _onTick() {
    final schedule = _schedule;
    final target = _runningTarget;
    if (!ref.mounted ||
        !state.isPlaying ||
        schedule == null ||
        target == null) {
      return;
    }
    _tickCount += 1;
    final nowMs = _clockMs();
    final rawDelta = nowMs - _runStartClockMs;
    final elapsedMs = (rawDelta == 0 && _tickCount > 0)
        ? _tickCount * _tickInterval.inMilliseconds
        : rawDelta;

    final tailMs = (!_looping && target == PlaybackTarget.deviceAudio)
        ? PianoPcmSynthesizer.releaseTailMs
        : 0;
    if (elapsedMs >= schedule.totalDurationMs + tailMs) {
      if (_looping) {
        _restartLoopPass(nowMs);
        return;
      }
      _haltPlayback(flushDeviceAudio: false);
      state = const ScorePlaybackState();
      return;
    }

    _advanceOutputsAt(elapsedMs);
    final window = schedule.sliceAtMs(
      elapsedMs.clamp(0, math.max(0, schedule.totalDurationMs - 1)),
    );
    if (window != null &&
        (window.sliceIndex != state.activeSliceIndex ||
            window.sliceOrdinal != state.activeSliceOrdinal)) {
      state = state.copyWith(
        activeSliceOrdinal: window.sliceOrdinal,
        activeSliceIndex: window.sliceIndex,
        activeMeasureNumber: window.measureNumber,
      );
    }
  }

  void _restartLoopPass(int nowMs) {
    final schedule = _schedule;
    if (schedule == null) {
      return;
    }
    if (_runningTarget == PlaybackTarget.midiPiano) {
      for (final active in _soundingMidiNotes) {
        _forTargetDevices(
          (id) => _midiSink.sendNoteOff(active.midiNote, deviceId: id),
        );
      }
      _soundingMidiNotes.clear();
    }
    _nextNoteCursor = 0;
    _synthesizedSamples = 0;
    _runStartClockMs = nowMs;
    _tickCount = 0;

    final firstWindow = schedule.sliceAtMs(0);
    if (firstWindow != null) {
      state = state.copyWith(
        activeSliceOrdinal: firstWindow.sliceOrdinal,
        activeSliceIndex: firstWindow.sliceIndex,
        activeMeasureNumber: firstWindow.measureNumber,
      );
    }
    _advanceOutputsAt(0);
  }

  void _advanceOutputsAt(int elapsedMs) {
    final schedule = _schedule;
    final target = _runningTarget;
    if (schedule == null || target == null) {
      return;
    }
    switch (target) {
      case PlaybackTarget.midiPiano:
        _pumpMidiEvents(schedule, elapsedMs);
      case PlaybackTarget.deviceAudio:
        _pumpDevicePcm(schedule, elapsedMs);
    }
  }

  void _pumpMidiEvents(ScorePlaybackSchedule schedule, int elapsedMs) {
    for (var i = _soundingMidiNotes.length - 1; i >= 0; i -= 1) {
      final span = _soundingMidiNotes[i];
      if (elapsedMs >= span.endMs) {
        _soundingMidiNotes.removeAt(i);
        _forTargetDevices(
          (id) => _midiSink.sendNoteOff(span.midiNote, deviceId: id),
        );
      }
    }
    while (_nextNoteCursor < schedule.notes.length) {
      final span = schedule.notes[_nextNoteCursor];
      if (span.startMs > elapsedMs) {
        break;
      }
      _nextNoteCursor += 1;
      if (elapsedMs < span.endMs) {
        _soundingMidiNotes.add(span);
        _forTargetDevices(
          (id) => _midiSink.sendNoteOn(
            span.midiNote,
            velocity: span.velocity,
            deviceId: id,
          ),
        );
      }
    }
  }

  void _forTargetDevices(
    Future<void> Function(String? deviceId) action, {
    List<String>? devicesOverride,
  }) {
    final ids = devicesOverride ?? _targetDeviceIds;
    if (ids.isEmpty) {
      unawaited(action(null));
      return;
    }
    for (final id in ids) {
      unawaited(action(id));
    }
  }

  void _pumpDevicePcm(ScorePlaybackSchedule schedule, int elapsedMs) {
    final sampleRate = _pcmOutput.sampleRate;
    if (sampleRate <= 0) {
      return;
    }
    final endMs = _looping
        ? schedule.totalDurationMs
        : schedule.totalDurationMs + PianoPcmSynthesizer.releaseTailMs;
    final totalSamples = (endMs * sampleRate) ~/ 1000;
    final chunkSamples = (_chunkDurationMs * sampleRate) ~/ 1000;
    final currentSynthesizedMs = (_synthesizedSamples * 1000) ~/ sampleRate;
    if (currentSynthesizedMs + _chunkDurationMs < elapsedMs) {
      _synthesizedSamples = math.min(
        totalSamples,
        (elapsedMs * sampleRate) ~/ 1000,
      );
    }

    var chunksThisTick = 0;
    while (_synthesizedSamples < totalSamples && chunksThisTick < 4) {
      if ((_synthesizedSamples * 1000) ~/ sampleRate >
          elapsedMs + _lookaheadMs) {
        break;
      }
      final count = math.min(chunkSamples, totalSamples - _synthesizedSamples);
      final bytes = _synthesizer.synthesizeWindow(
        notes: schedule.notes,
        startSample: _synthesizedSamples,
        sampleCount: count,
      );
      _synthesizedSamples += count;
      chunksThisTick += 1;
      unawaited(_pcmOutput.enqueuePcm16Mono(bytes));
    }
  }

  void _haltPlayback({required bool flushDeviceAudio}) {
    _tickTimer?.cancel();
    _tickTimer = null;
    final prevTarget = _runningTarget;
    final prevDevices = _targetDeviceIds;
    _runningTarget = null;
    _targetDeviceIds = const <String>[];
    _schedule = null;
    _soundingMidiNotes.clear();
    _nextNoteCursor = 0;
    _synthesizedSamples = 0;

    if (prevTarget == PlaybackTarget.midiPiano) {
      _forTargetDevices(
        (id) => _midiSink.sendAllNotesOff(deviceId: id),
        devicesOverride: prevDevices,
      );
    } else if (prevTarget == PlaybackTarget.deviceAudio && flushDeviceAudio) {
      unawaited(_pcmOutput.stop());
    }
  }
}

final scorePlaybackControllerProvider = NotifierProvider.autoDispose
    .family<
      ScorePlaybackController,
      ScorePlaybackState,
      ScorePlaybackSessionId
    >(ScorePlaybackController.new);
