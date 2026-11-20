import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';
import 'package:piano_exercises/features/piece_practice/domain/hand_mode.dart';

/// Loads and parses the `.mxl`/`.musicxml` payload for a catalog [ScoreVariant].
final variantScoreProvider = FutureProvider.autoDispose
    .family<ParsedScore, ScoreVariant>((ref, variant) async {
      ref.watch(catalogMutationVersionProvider);
      final fileStore = ref.watch(scoreFileStoreProvider);
      final parser = ref.watch(scoreParserProvider);
      final bytes = await fileStore.readScoreBytes(variant.storedRelativePath);
      return parser.parseBytes(bytes, fileName: variant.fileName);
    }, retry: (_, _) => null);

/// Live [Piece] lookup syncing variant/metadata edits while a score screen is open.
final livePieceProvider = FutureProvider.autoDispose.family<Piece?, String>((
  ref,
  pieceId,
) async {
  ref.watch(catalogControllerProvider);
  return ref.watch(catalogRepositoryProvider).getPieceById(pieceId);
}, retry: (_, _) => null);

/// Coalescing window grouping near-simultaneous Note On bursts into chords.
final practiceChordWindowProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 35);
});

/// Monotonic millisecond clock used by [PiecePracticeController]; overridable in tests.
final practiceClockMsProvider = Provider<int Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
});

/// Active [HandMode] for piece practice; kept separate so switching does not reset cursor.
class PracticeHandModeNotifier extends Notifier<HandMode> {
  @override
  HandMode build() => HandMode.both;

  void setMode(HandMode mode) => state = mode;
}

final practiceHandModeProvider =
    NotifierProvider.autoDispose<PracticeHandModeNotifier, HandMode>(
      PracticeHandModeNotifier.new,
    );

/// Pause toggle for piece practice MIDI evaluation across modals and pushed routes.
class PracticePausedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setPaused(bool paused) => state = paused;
}

final practicePausedProvider =
    NotifierProvider.autoDispose<PracticePausedNotifier, bool>(
      PracticePausedNotifier.new,
    );
