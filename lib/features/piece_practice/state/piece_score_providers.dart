import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piano_exercises/features/catalog/catalog.dart';

/// Loads and parses the `.mxl`/`.musicxml` payload for a catalog [ScoreVariant].
final variantScoreProvider = FutureProvider.autoDispose
    .family<ParsedScore, ScoreVariant>((ref, variant) async {
      final fileStore = ref.watch(scoreFileStoreProvider);
      final parser = ref.watch(scoreParserProvider);
      final bytes = await fileStore.readScoreBytes(variant.storedRelativePath);
      return parser.parseBytes(bytes, fileName: variant.fileName);
    }, retry: (_, _) => null);
