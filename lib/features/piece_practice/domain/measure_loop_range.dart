import 'package:piano_exercises/shared/music/music.dart';

/// Inclusive 0-based measure range used to loop a segment of a [Score].
final class MeasureLoopRange {
  const MeasureLoopRange({
    required this.startMeasureIndex,
    required this.endMeasureIndex,
  }) : assert(startMeasureIndex >= 0 && startMeasureIndex <= endMeasureIndex);

  final int startMeasureIndex;
  final int endMeasureIndex;

  bool containsMeasureIndex(int measureIndex) =>
      measureIndex >= startMeasureIndex && measureIndex <= endMeasureIndex;

  /// Clamps bounds into `0 .. measureCount - 1`, or returns `null` when empty.
  MeasureLoopRange? clampToMeasureCount(int measureCount) {
    if (measureCount <= 0) {
      return null;
    }
    final clampedStart = startMeasureIndex.clamp(0, measureCount - 1);
    final clampedEnd = endMeasureIndex.clamp(clampedStart, measureCount - 1);
    return MeasureLoopRange(
      startMeasureIndex: clampedStart,
      endMeasureIndex: clampedEnd,
    );
  }

  /// Formats the range using written measure numbers (falling back to 1-based).
  String formatLabel(List<ScoreMeasure> measures) {
    final startNum = _displayNumber(measures, startMeasureIndex);
    final endNum = _displayNumber(measures, endMeasureIndex);
    if (startMeasureIndex == endMeasureIndex) {
      return 'Loop M.$startNum';
    }
    return 'Loop M.$startNum\u2013$endNum';
  }

  static int _displayNumber(List<ScoreMeasure> measures, int index) {
    if (index >= 0 && index < measures.length) {
      final number = measures[index].measureNumber;
      if (number > 0) {
        return number;
      }
    }
    return index + 1;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MeasureLoopRange &&
            other.startMeasureIndex == startMeasureIndex &&
            other.endMeasureIndex == endMeasureIndex);
  }

  @override
  int get hashCode => Object.hash(startMeasureIndex, endMeasureIndex);
}
