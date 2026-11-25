import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/midi/midi.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_practice_controller.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_practice_body.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_fullscreen_view.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_bar.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// App bar rendered on [PieceScoreScreen] outside fullscreen mode.
class PieceScoreAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PieceScoreAppBar({
    super.key,
    required this.title,
    required this.isCompactHeight,
    required this.onEnterFullscreen,
    required this.onBeforeModal,
    required this.onAfterModal,
    this.onEditArrangement,
  });

  final String title;
  final bool isCompactHeight;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback onBeforeModal;
  final VoidCallback onAfterModal;
  final VoidCallback? onEditArrangement;

  @override
  Size get preferredSize => Size.fromHeight(isCompactHeight ? 48 : 56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: isCompactHeight ? 48 : null,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: <Widget>[
        if (onEditArrangement != null)
          IconButton(
            key: const ValueKey<String>('piece-score-edit-button'),
            tooltip: 'Edit arrangement',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEditArrangement,
          ),
        PieceScoreFullscreenButton(onPressed: onEnterFullscreen),
        MidiStatusActionButton(
          onBeforeOpen: onBeforeModal,
          onAfterClose: onAfterModal,
        ),
      ],
    );
  }
}

/// Builds [PieceScoreCursorBarData] when [loadedScore] and session state exist.
PieceScoreCursorBarData? buildPieceScoreCursorOrNull({
  required Score? loadedScore,
  required HandMode handMode,
  required PracticeSessionState? sessionState,
  required PiecePracticeController? controller,
  required VoidCallback? onOpenLoopSheet,
  VoidCallback? onStopPlayback,
}) {
  if (loadedScore == null || sessionState == null || controller == null) {
    return null;
  }
  return buildPieceScoreCursorBarData(
    score: loadedScore,
    handMode: handMode,
    sessionState: sessionState,
    controller: controller,
    onOpenLoopSheet: onOpenLoopSheet,
    onStopPlayback: onStopPlayback,
  );
}

/// Non-fullscreen column stacking [PieceScoreHeaderStrip] above [practiceBody].
class PieceScoreNormalBody extends StatelessWidget {
  const PieceScoreNormalBody({
    super.key,
    required this.data,
    required this.variantControl,
    required this.handControl,
    required this.cursor,
    required this.practiceBody,
    this.playbackControls,
  });

  final PiecePracticeScreenData data;
  final PieceScoreVariantControl variantControl;
  final PieceScoreHandControl handControl;
  final PieceScoreCursorBarData? cursor;
  final Widget practiceBody;
  final Widget? playbackControls;

  @override
  Widget build(BuildContext context) {
    final showHeader =
        data.asyncScore.value != null ||
        data.effectivePiece.variants.length > 1;
    final maxHeaderHeight = data.isCompactHeight
        ? math.max(96.0, data.maxHeight * 0.42)
        : math.max(120.0, data.maxHeight * 0.36);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showHeader) ...<Widget>[
          PieceScoreHeaderStrip(
            data: data,
            variantControl: variantControl,
            handControl: handControl,
            maxHeaderHeight: maxHeaderHeight,
            cursor: cursor,
            playbackControls: playbackControls,
          ),
          const Divider(height: 1),
        ],
        Expanded(child: practiceBody),
      ],
    );
  }
}

/// Scroll-bounded header strip hosting [PieceScoreHeaderBar] on [PieceScoreScreen].
class PieceScoreHeaderStrip extends StatelessWidget {
  const PieceScoreHeaderStrip({
    super.key,
    required this.data,
    required this.variantControl,
    required this.handControl,
    required this.maxHeaderHeight,
    this.cursor,
    this.playbackControls,
  });

  final PiecePracticeScreenData data;
  final PieceScoreVariantControl variantControl;
  final PieceScoreHandControl handControl;
  final double maxHeaderHeight;
  final PieceScoreCursorBarData? cursor;
  final Widget? playbackControls;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeaderHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          12,
          data.isCompactHeight ? 4 : 8,
          12,
          data.isCompactHeight ? 4 : 8,
        ),
        child: PieceScoreHeaderBar(
          piece: data.effectivePiece,
          variantControl: variantControl,
          handControl: handControl,
          cursor: cursor,
          playbackControls: playbackControls,
        ),
      ),
    );
  }
}
