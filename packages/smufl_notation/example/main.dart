import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:smufl_notation/smufl_notation.dart';

import 'spike_controls.dart';
import 'spike_fixtures.dart';

void main() {
  runApp(const SmuflSpikeApp());
}

/// Standalone `[M5]` SMuFL engraving spike and benchmark harness.
class SmuflSpikeApp extends StatelessWidget {
  const SmuflSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'SMuFL Notation Spike',
      debugShowCheckedModeBanner: false,
      color: const Color(0xFF1E40AF),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: const SmuflSpikeHome(),
    );
  }
}

/// Interactive benchmark view exercising layout, culling, dimming, and overlays.
class SmuflSpikeHome extends StatefulWidget {
  const SmuflSpikeHome({super.key});

  @override
  State<SmuflSpikeHome> createState() => _SmuflSpikeHomeState();
}

class _SmuflSpikeHomeState extends State<SmuflSpikeHome> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String> _metricsText = ValueNotifier<String>(
    'UI p95: -- | Raster p95: --',
  );
  final List<double> _uiMs = <double>[];
  final List<double> _rasterMs = <double>[];

  bool _usePolyphonic = false;
  int _activeSliceIndex = 0;
  SmuflClef? _dimmedClef;
  bool _showWrongNotes = false;
  bool _compactWidth = false;
  bool _suppressNextMetricsFrame = false;

  NotationScore get _score => _usePolyphonic
      ? SpikeFixtures.polyphonicGrandStaff
      : SpikeFixtures.simplifiedMelodyBass;

  int get _maxSliceIndex => _score.measures.expand((m) => m.slices).length - 1;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _scrollController.dispose();
    _metricsText.dispose();
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) {
      return;
    }
    for (final t in timings) {
      _uiMs.add(t.buildDuration.inMicroseconds / 1000.0);
      _rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
    if (_uiMs.length > 60) {
      _uiMs.removeRange(0, _uiMs.length - 60);
      _rasterMs.removeRange(0, _rasterMs.length - 60);
    }
    if (_suppressNextMetricsFrame) {
      _suppressNextMetricsFrame = false;
      return;
    }
    _suppressNextMetricsFrame = true;
    final uiP95 = _percentile95(_uiMs).toStringAsFixed(1);
    final rasterP95 = _percentile95(_rasterMs).toStringAsFixed(1);
    _metricsText.value = 'UI p95: ${uiP95}ms | Raster p95: ${rasterP95}ms';
  }

  static double _percentile95(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }
    final sorted = List<double>.of(values)..sort();
    return sorted[(0.95 * (sorted.length - 1)).round()];
  }

  List<WrongNoteOverlay> get _overlays {
    if (!_showWrongNotes) {
      return const <WrongNoteOverlay>[];
    }
    return <WrongNoteOverlay>[
      WrongNoteOverlay(
        sliceIndex: _activeSliceIndex,
        notes: <NotationNote>[
          NotationNote(
            staffStep: 12,
            clef: SmuflClef.treble,
            accidental: SmuflAccidental.sharp,
            showAccidental: true,
          ),
          NotationNote(staffStep: 1, clef: SmuflClef.treble),
          NotationNote(staffStep: 2, clef: SmuflClef.treble),
          NotationNote(
            staffStep: -5,
            clef: SmuflClef.bass,
            accidental: SmuflAccidental.flat,
            showAccidental: true,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(120.0, constraints.maxHeight * 0.45),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: SpikeControls(
                        usePolyphonic: _usePolyphonic,
                        dimmedClef: _dimmedClef,
                        showWrongNotes: _showWrongNotes,
                        compactWidth: _compactWidth,
                        metricsText: _metricsText,
                        onSelectSimplified: () => setState(() {
                          _usePolyphonic = false;
                          _activeSliceIndex = 0;
                        }),
                        onSelectPolyphonic: () => setState(() {
                          _usePolyphonic = true;
                          _activeSliceIndex = 0;
                        }),
                        onPrevSlice: () => setState(() {
                          _activeSliceIndex = math.max(
                            0,
                            _activeSliceIndex - 1,
                          );
                        }),
                        onNextSlice: () => setState(() {
                          _activeSliceIndex = math.min(
                            _maxSliceIndex,
                            _activeSliceIndex + 1,
                          );
                        }),
                        onSelectHand: (clef) =>
                            setState(() => _dimmedClef = clef),
                        onToggleWrongNotes: () =>
                            setState(() => _showWrongNotes = !_showWrongNotes),
                        onSelectCompactWidth: (compact) =>
                            setState(() => _compactWidth = compact),
                      ),
                    ),
                  ),
                  const ColoredBox(
                    color: Color(0xFFE2E8F0),
                    child: SizedBox(height: 1),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _compactWidth ? 340.0 : double.infinity,
                        ),
                        child: GrandStaffScoreView(
                          score: _score,
                          controller: _scrollController,
                          activeSliceIndex: _activeSliceIndex,
                          dimmedClef: _dimmedClef,
                          wrongNoteOverlays: _overlays,
                          onSliceTapped: (idx) =>
                              setState(() => _activeSliceIndex = idx),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
