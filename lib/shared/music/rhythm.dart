/// Exact non-negative rational beat duration expressed in quarter-note beats.
final class RationalBeats implements Comparable<RationalBeats> {
  const RationalBeats._(this.numerator, this.denominator);

  const RationalBeats.zero() : numerator = 0, denominator = 1;

  /// Creates a GCD-normalized [RationalBeats] for `numerator / denominator`.
  factory RationalBeats(int numerator, [int denominator = 1]) {
    if (denominator <= 0) {
      throw RangeError.value(denominator, 'denominator', 'must be positive');
    }
    if (numerator < 0) {
      throw RangeError.value(numerator, 'numerator', 'must be non-negative');
    }
    if (numerator == 0) {
      return const RationalBeats.zero();
    }
    final divisor = _gcd(numerator, denominator);
    return RationalBeats._(numerator ~/ divisor, denominator ~/ divisor);
  }

  final int numerator;
  final int denominator;

  bool get isZero => numerator == 0;

  double get toDouble => numerator / denominator;

  RationalBeats operator +(RationalBeats other) {
    final divisor = _gcd(denominator, other.denominator);
    final leftFactor = other.denominator ~/ divisor;
    final rightFactor = denominator ~/ divisor;
    return RationalBeats(
      (numerator * leftFactor) + (other.numerator * rightFactor),
      leftFactor * denominator,
    );
  }

  RationalBeats operator -(RationalBeats other) {
    final divisor = _gcd(denominator, other.denominator);
    final leftFactor = other.denominator ~/ divisor;
    final rightFactor = denominator ~/ divisor;
    final diff = (numerator * leftFactor) - (other.numerator * rightFactor);
    if (diff < 0) {
      throw RangeError('RationalBeats subtraction cannot be negative.');
    }
    return RationalBeats(diff, leftFactor * denominator);
  }

  RationalBeats operator *(int factor) {
    if (factor < 0) {
      throw RangeError.value(factor, 'factor', 'must be non-negative');
    }
    return RationalBeats(numerator * factor, denominator);
  }

  bool operator <(RationalBeats other) => compareTo(other) < 0;

  bool operator <=(RationalBeats other) => compareTo(other) <= 0;

  bool operator >(RationalBeats other) => compareTo(other) > 0;

  bool operator >=(RationalBeats other) => compareTo(other) >= 0;

  @override
  int compareTo(RationalBeats other) {
    return (numerator * other.denominator).compareTo(
      other.numerator * denominator,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RationalBeats &&
            other.numerator == numerator &&
            other.denominator == denominator);
  }

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() =>
      denominator == 1 ? '$numerator' : '$numerator/$denominator';

  static int _gcd(int a, int b) {
    var x = a;
    var y = b;
    while (y != 0) {
      final rem = x % y;
      x = y;
      y = rem;
    }
    return x;
  }
}

/// Written note/rest base duration values in quarter-note beat ratios.
enum NoteBaseDuration {
  whole(4, 1),
  half(2, 1),
  quarter(1, 1),
  eighth(1, 2),
  sixteenth(1, 4),
  thirtySecond(1, 8),
  sixtyFourth(1, 16);

  const NoteBaseDuration(this._numerator, this._denominator);

  final int _numerator;
  final int _denominator;

  RationalBeats get quarterBeats => RationalBeats._(_numerator, _denominator);
}

/// Written rhythmic value pairing [base], augmentation [dots], and exact [quarterBeats].
final class DurationValue {
  DurationValue({
    required this.base,
    this.dots = 0,
    RationalBeats? quarterBeats,
  }) : quarterBeats = quarterBeats ?? _computeDottedBeats(base, dots) {
    RangeError.checkValueInInterval(dots, 0, 2, 'dots');
    if (this.quarterBeats.isZero) {
      throw RangeError.value(0, 'quarterBeats', 'must be positive');
    }
  }

  final NoteBaseDuration base;
  final int dots;
  final RationalBeats quarterBeats;

  static RationalBeats _computeDottedBeats(NoteBaseDuration base, int dots) {
    RangeError.checkValueInInterval(dots, 0, 2, 'dots');
    final factorNumerator = (1 << (dots + 1)) - 1;
    final factorDenominator = 1 << dots;
    final unscaled = base.quarterBeats;
    return RationalBeats(
      unscaled.numerator * factorNumerator,
      unscaled.denominator * factorDenominator,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DurationValue &&
            other.base == base &&
            other.dots == dots &&
            other.quarterBeats == quarterBeats);
  }

  @override
  int get hashCode => Object.hash(base, dots, quarterBeats);
}

/// Meter signature validated to `1..32` beats and power-of-two denominators.
final class TimeSignature {
  const TimeSignature._(this.beats, this.beatType);

  /// Creates a [TimeSignature] after validating [beats] (`1..32`) and [beatType].
  factory TimeSignature(int beats, int beatType) {
    RangeError.checkValueInInterval(beats, 1, 32, 'beats');
    if (!_validBeatTypes.contains(beatType)) {
      throw ArgumentError.value(
        beatType,
        'beatType',
        'must be one of 1, 2, 4, 8, 16, 32',
      );
    }
    return TimeSignature._(beats, beatType);
  }

  static const TimeSignature common = TimeSignature._(4, 4);
  static const Set<int> _validBeatTypes = <int>{1, 2, 4, 8, 16, 32};

  final int beats;
  final int beatType;

  RationalBeats get measureQuarterBeats => RationalBeats(beats * 4, beatType);

  String get label => '$beats/$beatType';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TimeSignature &&
            other.beats == beats &&
            other.beatType == beatType);
  }

  @override
  int get hashCode => Object.hash(beats, beatType);
}

/// Quarter-note tempo marking validated to `1..999` BPM.
final class TempoMark {
  const TempoMark._(this.bpm);

  /// Creates a [TempoMark] after validating [bpm] is in `1..999`.
  factory TempoMark(int bpm) {
    RangeError.checkValueInInterval(bpm, 1, 999, 'bpm');
    return TempoMark._(bpm);
  }

  final int bpm;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is TempoMark && other.bpm == bpm);
  }

  @override
  int get hashCode => bpm.hashCode;
}
