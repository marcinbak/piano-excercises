import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:smufl_notation/src/grand_staff_score_painter.dart';
import 'package:smufl_notation/src/notation_model.dart';
import 'package:smufl_notation/src/score_layout_engine.dart';
import 'package:smufl_notation/src/score_layout_types.dart';

/// Scrollable, responsive SMuFL grand-staff score widget with cached layout.
class GrandStaffScoreView extends StatefulWidget {
  const GrandStaffScoreView({
    required this.score,
    super.key,
    this.style = const ScoreStyle(),
    this.activeSliceIndex,
    this.dimmedClef,
    this.wrongNoteOverlays = const <WrongNoteOverlay>[],
    this.onSliceTapped,
    this.controller,
  });

  final NotationScore score;
  final ScoreStyle style;
  final int? activeSliceIndex;
  final SmuflClef? dimmedClef;
  final List<WrongNoteOverlay> wrongNoteOverlays;
  final ValueChanged<int>? onSliceTapped;
  final ScrollController? controller;

  @override
  State<GrandStaffScoreView> createState() => _GrandStaffScoreViewState();
}

class _GrandStaffScoreViewState extends State<GrandStaffScoreView> {
  ScrollController? _ownedController;
  final ValueNotifier<Rect?> _visibleRect = ValueNotifier<Rect?>(null);

  EngravedScoreLayout? _cachedLayout;
  NotationScore? _lastScore;
  ScoreStyle? _lastStyle;
  double? _lastWidth;
  double _viewportWidth = 0;
  double _viewportHeight = 0;

  ScrollController get _controller => widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = ScrollController();
    }
    _controller.addListener(_syncVisibleRect);
  }

  @override
  void didUpdateWidget(covariant GrandStaffScoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncVisibleRect);
      if (widget.controller == null && _ownedController == null) {
        _ownedController = ScrollController();
      } else if (widget.controller != null) {
        _ownedController?.dispose();
        _ownedController = null;
      }
      _controller.addListener(_syncVisibleRect);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.score != widget.score ||
        oldWidget.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibleRect());
    }
    if (widget.activeSliceIndex != oldWidget.activeSliceIndex &&
        widget.activeSliceIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = widget.activeSliceIndex;
        if (target != null) {
          _scrollToActiveSlice(target);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncVisibleRect);
    _ownedController?.dispose();
    _visibleRect.dispose();
    super.dispose();
  }

  EngravedScoreLayout _layoutForWidth(double width) {
    final cached = _cachedLayout;
    if (cached != null &&
        _lastScore == widget.score &&
        _lastStyle == widget.style &&
        _lastWidth == width) {
      return cached;
    }
    final next = ScoreLayoutEngine.layout(
      score: widget.score,
      availableWidth: width,
      style: widget.style,
    );
    _cachedLayout = next;
    _lastScore = widget.score;
    _lastStyle = widget.style;
    _lastWidth = width;
    return next;
  }

  void _syncVisibleRect() {
    if (!mounted || _viewportWidth <= 0 || _viewportHeight <= 0) {
      return;
    }
    var top = 0.0;
    if (_controller.hasClients) {
      final pos = _controller.position;
      top = pos.hasContentDimensions
          ? pos.pixels.clamp(0.0, pos.maxScrollExtent)
          : math.max(0.0, pos.pixels);
    }
    final next = Rect.fromLTWH(0, top, _viewportWidth, _viewportHeight);
    if (_visibleRect.value != next) {
      _visibleRect.value = next;
    }
  }

  void _scrollToActiveSlice(int sliceIndex) {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    if (!position.hasViewportDimension) {
      return;
    }
    final placement = _cachedLayout?.slicePlacement(sliceIndex);
    if (placement == null) {
      return;
    }
    final sys = placement.system;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    final pad = widget.style.staffSpace;
    if (sys.topY >= viewTop && sys.bottomY <= viewBottom) {
      return;
    }
    final target = (sys.topY - pad).clamp(0.0, position.maxScrollExtent);
    if ((target - viewTop).abs() < 1.0) {
      return;
    }
    // Avoid `unawaited_futures` by explicitly ignoring scroll animation future.
    _controller
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? math.max(1.0, constraints.maxWidth)
            : 360.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 480.0;
        if (width != _viewportWidth || height != _viewportHeight) {
          _viewportWidth = width;
          _viewportHeight = height;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncVisibleRect();
          });
        }

        final layout = _layoutForWidth(width);
        final initialRect =
            _visibleRect.value ?? Rect.fromLTWH(0, 0, width, height);

        return SingleChildScrollView(
          controller: _controller,
          child: GestureDetector(
            behavior: widget.onSliceTapped == null
                ? HitTestBehavior.deferToChild
                : HitTestBehavior.opaque,
            onTapUp: widget.onSliceTapped == null
                ? null
                : (details) {
                    final idx = layout.sliceAtOffset(details.localPosition);
                    if (idx != null) {
                      widget.onSliceTapped!(idx);
                    }
                  },
            child: ValueListenableBuilder<Rect?>(
              valueListenable: _visibleRect,
              builder: (context, rect, _) {
                final rawRect = rect ?? initialRect;
                final maxTop = math.max(0.0, layout.totalSize.height - height);
                final effectiveRect = Rect.fromLTWH(
                  0,
                  rawRect.top.clamp(0.0, maxTop),
                  width,
                  height,
                );
                return RepaintBoundary(
                  child: CustomPaint(
                    size: layout.totalSize,
                    painter: GrandStaffScorePainter(
                      layout: layout,
                      activeSliceIndex: widget.activeSliceIndex,
                      dimmedClef: widget.dimmedClef,
                      wrongNoteOverlays: widget.wrongNoteOverlays,
                      visibleRect: effectiveRect,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
