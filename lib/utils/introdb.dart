import 'dart:convert';
import 'package:http/http.dart' as http;

class IntroDbApi {
  static const String apiUrl = "https://api.introdb.app";
  static const String skipTimeEndpoint = "/segments";

  Future<EpisodeSkipTimes?> getSkipTimes(SkipSearchQuery query) async {
    if (query.imdbId == null ||
        query.episodeNumber == null ||
        query.seasonNumber == null) {
      return null;
    }
    String imdbId = query.imdbId!;
    String seasonNumber = query.seasonNumber!;
    String episodeNumber = query.episodeNumber!;

    String uri =
        "$apiUrl$skipTimeEndpoint?imdb_id=$imdbId&season=$seasonNumber&episode=$episodeNumber";

    try {
      final response = await http.get(Uri.parse(uri));

      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data = jsonDecode(response.body);

      SkipIntervals? op;
      SkipIntervals? ed;
      SkipIntervals? recap;

      if (data['intro'] != null) {
        op = SkipIntervals(
          start: data['intro']['start_sec'].toInt(),
          end: data['intro']['end_sec'].toInt(),
        );
      }
      if (data['outro'] != null) {
        ed = SkipIntervals(
          start: data['outro']['start_sec'].toInt(),
          end: data['outro']['end_sec'].toInt(),
        );
      }
      if (data['recap'] != null) {
        recap = SkipIntervals(
          start: data['recap']['start_sec'].toInt(),
          end: data['recap']['end_sec'].toInt(),
        );
      }

      if (op != null || ed != null || recap != null) {
        return EpisodeSkipTimes(op: op, ed: ed, recap: recap);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}

class EpisodeSkipTimes {
  final SkipIntervals? op;
  final SkipIntervals? ed;
  final SkipIntervals? recap;

  EpisodeSkipTimes({this.op, this.ed, this.recap});
}

class SkipIntervals {
  final int start;
  final int end;

  SkipIntervals({required this.start, required this.end});
}

class SkipSearchQuery {
  final String? imdbId;
  final String? episodeNumber;
  final String? seasonNumber;

  SkipSearchQuery({this.imdbId, this.episodeNumber, this.seasonNumber});
}
