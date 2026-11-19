import 'package:smufl_notation/smufl_notation.dart';

import 'spike_polyphonic_fixture.dart';
import 'spike_simplified_fixture.dart';

/// Cached `[M5]` sample scores for the benchmark harness and tests.
abstract final class SpikeFixtures {
  static final NotationScore simplifiedMelodyBass =
      buildSimplifiedMelodyBassScore();
  static final NotationScore polyphonicGrandStaff =
      buildPolyphonicGrandStaffScore();
}
