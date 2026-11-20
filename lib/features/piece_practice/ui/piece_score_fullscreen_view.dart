import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Returns initial [RotatedBox.quarterTurns] when entering fullscreen.
///
/// Portrait phones (`shortestSide < 600` and `width < height`) start rotated
/// `90°` (`1`) so portrait-locked iPhones open directly in landscape; tablets
/// and already-landscape viewports start unrotated (`0`).
int defaultFullscreenQuarterTurns(Size screenSize) {
  final isPortraitPhone =
      screenSize.shortestSide < 600 && screenSize.width < screenSize.height;
  return isPortraitPhone ? 1 : 0;
}

/// Toggles immersive OS system-bar visibility for fullscreen score mode.
Future<void> setFullscreenSystemUiMode({required bool fullscreen}) {
  return SystemChrome.setEnabledSystemUIMode(
    fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );
}

/// Immutable UI state for [PieceScoreScreen] fullscreen and 90-degree rotation.
final class PieceScoreFullscreenState {
  const PieceScoreFullscreenState({
    this.isFullscreen = false,
    this.quarterTurns,
  });

  final bool isFullscreen;
  final int? quarterTurns;

  int effectiveQuarterTurns(Size screenSize) =>
      quarterTurns ?? defaultFullscreenQuarterTurns(screenSize);

  PieceScoreFullscreenState enter(Size screenSize) {
    if (isFullscreen) {
      return this;
    }
    unawaited(setFullscreenSystemUiMode(fullscreen: true));
    return PieceScoreFullscreenState(
      isFullscreen: true,
      quarterTurns: effectiveQuarterTurns(screenSize),
    );
  }

  PieceScoreFullscreenState exit() {
    if (!isFullscreen) {
      return this;
    }
    unawaited(setFullscreenSystemUiMode(fullscreen: false));
    return PieceScoreFullscreenState(
      isFullscreen: false,
      quarterTurns: quarterTurns,
    );
  }

  PieceScoreFullscreenState rotateQuarterTurn(Size screenSize) {
    return PieceScoreFullscreenState(
      isFullscreen: isFullscreen,
      quarterTurns: (effectiveQuarterTurns(screenSize) + 1) % 4,
    );
  }
}

/// AppBar action button that enters fullscreen score mode when a score is loaded.
class PieceScoreFullscreenButton extends StatelessWidget {
  const PieceScoreFullscreenButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey<String>('score_fullscreen_button'),
      tooltip: 'Fullscreen',
      onPressed: onPressed,
      icon: const Icon(Icons.fullscreen),
    );
  }
}

/// Fullscreen score wrapper with 90-degree step rotation and floating controls.
class PieceScoreFullscreenView extends StatelessWidget {
  const PieceScoreFullscreenView({
    super.key,
    required this.quarterTurns,
    required this.onRotateQuarterTurn,
    required this.onExitFullscreen,
    required this.child,
  });

  final int quarterTurns;
  final VoidCallback onRotateQuarterTurn;
  final VoidCallback onExitFullscreen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      key: const ValueKey<String>('score_fullscreen_rotated_box'),
      quarterTurns: quarterTurns,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child,
          Positioned(
            right: 12,
            bottom: 12,
            child: _FullscreenControlsPill(
              onRotateQuarterTurn: onRotateQuarterTurn,
              onExitFullscreen: onExitFullscreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenControlsPill extends StatelessWidget {
  const _FullscreenControlsPill({
    required this.onRotateQuarterTurn,
    required this.onExitFullscreen,
  });

  final VoidCallback onRotateQuarterTurn;
  final VoidCallback onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey<String>('score_fullscreen_controls'),
      elevation: 2,
      color: colorScheme.secondaryContainer.withValues(alpha: 0.92),
      shape: StadiumBorder(
        side: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('score_rotate_button'),
              tooltip: 'Rotate 90°',
              visualDensity: VisualDensity.compact,
              color: colorScheme.onSecondaryContainer,
              icon: const Icon(Icons.rotate_right),
              onPressed: onRotateQuarterTurn,
            ),
            IconButton(
              key: const ValueKey<String>('score_exit_fullscreen_button'),
              tooltip: 'Exit fullscreen',
              visualDensity: VisualDensity.compact,
              color: colorScheme.onSecondaryContainer,
              icon: const Icon(Icons.fullscreen_exit),
              onPressed: onExitFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}
