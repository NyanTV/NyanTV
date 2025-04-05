import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nyantv/utils/logger.dart';

class SubtitleTranslator {
  static final Map<String, String> _cache = {};

  static const instances = [
    'https://lingva.ml',
    'https://translate.plausibility.cloud',
    'https://translate.tiekoetter.com',
    'https://lingva.lunar.icu',
    'https://lingva.thedaviddelta.com',
    'https://lingva.pussthecat.org',
  ];

  static const _maxCacheSize = 2000;

  static String? getCached(String targetLang, String text) =>
      _cache['$targetLang:$text'];

  static void _addToCache(String key, String value) {
    if (_cache.length >= _maxCacheSize) {
      final toRemove = _cache.keys.take(500).toList();
      for (final k in toRemove) {
        _cache.remove(k);
      }
    }
    _cache[key] = value;
  }

  static Future<String?> translateWithInstance(
      String text, String targetLang, String instance) async {
    if (text.isEmpty) return text;
    try {
      final response = await http
          .get(Uri.parse(
              '$instance/api/v1/auto/$targetLang/${Uri.encodeComponent(text)}'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final translated = body['translation'] as String?;
        if (translated == null || translated.isEmpty) return null;
        _addToCache('$targetLang:$text', translated);
        return translated;
      }
      return null;
    } catch (e) {
      Logger.e('[SubtitleTranslator] $instance failed: $e');
      return null;
    }
  }

  static Future<String> translate(String text, String targetLang) async {
    if (text.isEmpty || targetLang == 'none') return text;
    final cacheKey = '$targetLang:$text';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    for (final instance in instances) {
      final result = await translateWithInstance(text, targetLang, instance);
      if (result != null) return result;
    }
    return text;
  }

  static const Map<String, String> languages = {
    'am': 'Amharic',
    'ar': 'Arabic',
    'as': 'Assamese',
    'bn': 'Bengali',
    'brx': 'Bodo',
    'my': 'Burmese',
    'zh-CN': 'Chinese (Simplified)',
    'zh-TW': 'Chinese (Traditional)',
    'hr': 'Croatian',
    'cs': 'Czech',
    'da': 'Danish',
    'doi': 'Dogri',
    'nl': 'Dutch',
    'en': 'English',
    'en-US': 'English (US)',
    'fi': 'Finnish',
    'tl': 'Filipino',
    'fr': 'French',
    'de': 'German',
    'el': 'Greek',
    'gu': 'Gujarati',
    'ha': 'Hausa',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'hu': 'Hungarian',
    'ig': 'Igbo',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'kn': 'Kannada',
    'ks': 'Kashmiri',
    'kk': 'Kazakh',
    'km': 'Khmer',
    'kok': 'Konkani',
    'ko': 'Korean',
    'lo': 'Lao',
    'es-419': 'Latin American Spanish',
    'lv': 'Latvian',
    'lt': 'Lithuanian',
    'mk': 'Macedonian',
    'ma': 'Maithili',
    'ms': 'Malay',
    'ml': 'Malayalam',
    'mni-Mtei': 'Meitei (Manipuri)',
    'mr': 'Marathi',
    'ne': 'Nepali',
    'no': 'Norwegian',
    'or': 'Odia',
    'fa': 'Persian',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'pt-BR': 'Portuguese (Brazil)',
    'pa': 'Punjabi',
    'qu': 'Quechua',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sa': 'Sanskrit',
    'sat': 'Santali',
    'gd': 'Scottish Gaelic',
    'sr': 'Serbian',
    'si': 'Sinhala',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'es': 'Spanish',
    'sw': 'Swahili',
    'sv': 'Swedish',
    'ta': 'Tamil',
    'te': 'Telugu',
    'th': 'Thai',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'uz': 'Uzbek',
    'vi': 'Vietnamese',
    'cy': 'Welsh',
    'yo': 'Yoruba',
    'zu': 'Zulu',
  };
}
