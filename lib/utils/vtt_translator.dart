import 'package:nyantv/utils/subtitle_translator.dart';

class VttTranslator {
  static const _maxCuesPerChunk = 15;

  static Future<String> translate(String vttContent, String targetLang) async {
    if (targetLang == 'none') return vttContent;

    final blocks = vttContent.split(RegExp(r'\r?\n\r?\n'));
    final cueIndices = <int>[];
    final cueTexts = <String>[];

    for (int i = 0; i < blocks.length; i++) {
      final lines = blocks[i].trim().split(RegExp(r'\r?\n'));
      final tsIndex = lines.indexWhere((l) => l.contains('-->'));
      if (tsIndex != -1 && tsIndex + 1 < lines.length) {
        cueIndices.add(i);
        cueTexts.add(lines.sublist(tsIndex + 1).join('\n'));
      }
    }

    final translated = await _translateInChunks(cueTexts, targetLang);

    for (int j = 0; j < cueIndices.length; j++) {
      final i = cueIndices[j];
      final lines = blocks[i].trim().split(RegExp(r'\r?\n'));
      final tsIndex = lines.indexWhere((l) => l.contains('-->'));
      if (tsIndex != -1) {
        blocks[i] =
            '${lines.sublist(0, tsIndex + 1).join('\n')}\n${translated[j]}';
      }
    }

    return blocks.join('\n\n');
  }

  static Future<List<String>> _translateInChunks(
      List<String> texts, String targetLang) async {
    final results = List<String>.filled(texts.length, '');
    int start = 0;

    while (start < texts.length) {
      final end = (start + _maxCuesPerChunk).clamp(0, texts.length);
      final chunk = texts.sublist(start, end);
      final joined = chunk.join('\n\n');

      final translatedJoined =
          await SubtitleTranslator.translate(joined, targetLang);
      final parts = translatedJoined.split(RegExp(r'\n\n'));

      for (int i = 0; i < chunk.length; i++) {
        results[start + i] = i < parts.length ? parts[i] : texts[start + i];
      }

      start = end;
      if (start < texts.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return results;
  }
}
