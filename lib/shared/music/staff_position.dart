import 'package:piano_exercises/shared/music/clef.dart';

/// Direction of required ledger lines relative to the five-line staff.
enum LedgerDirection { none, below, above }

/// Vertical position on a five-line [Clef] staff in diatonic steps.
///
/// `0` is the bottom line and `8` is the top line; even values lie on lines
/// and odd values lie in spaces.
final class StaffPosition {
  const StaffPosition({required this.clef, required this.stepsFromBottomLine});

  /// Maps an absolute [diatonicStep] (`octave * 7 + note.index`) onto [clef].
  factory StaffPosition.forDiatonicStep({
    required Clef clef,
    required int diatonicStep,
  }) {
    return StaffPosition(
      clef: clef,
      stepsFromBottomLine: diatonicStep - clef.bottomLineDiatonicStep,
    );
  }

  final Clef clef;
  final int stepsFromBottomLine;

  bool get isOnLine => stepsFromBottomLine.isEven;

  bool get isInSpace => stepsFromBottomLine.isOdd;

  bool get isInsideStaff =>
      stepsFromBottomLine >= 0 && stepsFromBottomLine <= 8;

  /// Returns `none` whenever zero ledger lines are needed (including steps `-1` and `9`).
  LedgerDirection get ledgerDirection {
    if (stepsFromBottomLine <= -2) {
      return LedgerDirection.below;
    }
    if (stepsFromBottomLine >= 10) {
      return LedgerDirection.above;
    }
    return LedgerDirection.none;
  }

  int get ledgerLineCount {
    if (stepsFromBottomLine < 0) {
      return (-stepsFromBottomLine) ~/ 2;
    }
    if (stepsFromBottomLine > 8) {
      return (stepsFromBottomLine - 8) ~/ 2;
    }
    return 0;
  }

  /// Unmodifiable staff-relative even steps (`[-2, -4, ...]` or `[10, 12, ...]`).
  List<int> get ledgerLineSteps {
    final count = ledgerLineCount;
    if (count == 0) {
      return const <int>[];
    }
    return List<int>.unmodifiable(
      stepsFromBottomLine < 0
          ? List<int>.generate(count, (index) => -2 * (index + 1))
          : List<int>.generate(count, (index) => 8 + (2 * (index + 1))),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StaffPosition &&
            other.clef == clef &&
            other.stepsFromBottomLine == stepsFromBottomLine);
  }

  @override
  int get hashCode => Object.hash(clef, stepsFromBottomLine);
}
