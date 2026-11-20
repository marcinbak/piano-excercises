import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';
import 'package:piano_exercises/features/piece_practice/state/piece_practice_controller.dart';
import 'package:piano_exercises/features/piece_practice/state/practice_session_state.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_practice_body.dart';
import 'package:piano_exercises/features/piece_practice/ui/piece_score_header_bar.dart';
import 'package:piano_exercises/shared/music/music.dart';

/// Builds [PieceScoreCursorBarData] when [loadedScore] and session state exist.
PieceScoreCursorBarData? buildPieceScoreCursorOrNull({
  required Score? loadedScore,
  required HandMode handMode,
  required PracticeSessionState? sessionState,
  required PiecePracticeController? controller,
  required VoidCallback? onOpenLoopSheet,
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
  );
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
  });

  final PiecePracticeScreenData data;
  final PieceScoreVariantControl variantControl;
  final PieceScoreHandControl handControl;
  final double maxHeaderHeight;
  final PieceScoreCursorBarData? cursor;

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
        ),
      ),
    );
  }
}
