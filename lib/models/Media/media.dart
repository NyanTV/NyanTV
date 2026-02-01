import 'package:nyantv/utils/logger.dart';

import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/models/Anilist/anilist_media_user.dart';
import 'package:nyantv/models/Media/character.dart';
import 'package:nyantv/models/Media/relation.dart';
import 'package:nyantv/models/Offline/Hive/chapter.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:nyantv/models/models_convertor/carousel/carousel_data.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';

class Media {
  String id;
  String idMal;
  String title;
  String romajiTitle;
  String description;
  String poster;
  String? cover;
  String totalEpisodes;
  String type;
  String color;
  String season;
  String premiered;
  String duration;
  String status;
  String rating;
  String popularity;
  String format;
  String aired;
  ItemType mediaType;
  List<DEpisode>? mediaContent;
  List<Chapter>? altMediaContent;
  List<String> genres;
  List<String>? studios;
  List<Character>? characters;
  List<Relation>? relations;
  List<Media> recommendations;
  NextAiringEpisode? nextAiringEpisode;
  List<Ranking> rankings;
  ServicesType serviceType;
  DateTime? createdAt;
  bool? isAdult;
  String? sourceName;

  Media(
      {this.id = '0',
      this.idMal = '0',
      this.isAdult,
      this.mediaType = ItemType.anime,
      this.title = '?',
      this.color = '',
      this.romajiTitle = '?',
      this.description = '?',
      this.poster = '?',
      this.cover,
      this.totalEpisodes = '?',
      this.type = '?',
      this.season = '?',
      this.premiered = '?',
      this.duration = '?',
      this.status = 'ONGOING.. probably?',
      this.rating = '?',
      this.popularity = '?',
      this.format = '?',
      this.aired = '?',
      this.genres = const [],
      this.studios,
      this.characters,
      this.altMediaContent,
      this.relations,
      this.recommendations = const [],
      this.nextAiringEpisode,
      this.rankings = const [],
      this.mediaContent,
      required this.serviceType,
      this.sourceName,
      DateTime? createdAt})
      : createdAt = DateTime.now();

  factory Media.froDMedia(DMedia anime, ItemType type) {
    return Media(
      id: anime.url ?? '',
      title: anime.title ?? "Unknown Title",
      romajiTitle: anime.title ?? "Unknown Title",
      description: anime.description ?? "No description available.",
      poster: anime.cover ?? "",
      cover: anime.cover,
      totalEpisodes: anime.episodes?.length.toString() ?? '??',
      status: '??',
      mediaType: type,
      aired: 'Unknown',
      genres: anime.genre ?? [],
      studios: null,
      characters: [],
      relations: [],
      recommendations: [],
      nextAiringEpisode: null,
      rankings: [],
      mediaContent: anime.episodes,
      serviceType: ServicesType.extensions,
    );
  }

  factory Media.fromJson(Map<String, dynamic> json) {
    ItemType type = json['type'] == "ANIME" ? ItemType.anime : ItemType.novel;
    return Media(
      id: json['id'].toString(),
      idMal: json['idMal'].toString(),
      romajiTitle: json['title']['romaji'] ?? '?',
      title: json['title']['english'] ?? json['title']['romaji'] ?? '?',
      description: json['description'] ?? '?',
      poster: json['coverImage']['large'] ?? '?',
      isAdult: json['isAdult'] ?? false,
      color: json['coverImage']['color'] ?? '',
      cover: json['bannerImage'],
      totalEpisodes: (json['episodes'] as int?)?.toString() ?? '?',
      type: json['type'] ?? '?',
      season: json['season'] ?? '?',
      premiered: '${json['season'] ?? '?'} ${json['seasonYear'] ?? '?'}',
      duration: '${json['duration'] ?? '?'}m',
      status: json['status'] ?? '?',
      rating: ((json['averageScore'] ?? 0) / 10).toString(),
      popularity: json['popularity']?.toString() ?? '6900',
      format: json['format'] ?? '?',
      aired: _parseDateRange(json['startDate'], json['endDate']),
      genres: List<String>.from(json['genres'] ?? []),
      studios: (json['studios']['nodes'] as List)
          .map((el) => el['name'].toString())
          .toList(),
      characters: (json['characters']['edges'] as List)
          .map((character) => Character.fromJson(character))
          .toList(),
      relations: (json['relations']['edges'] as List)
          .map((relation) => Relation.fromJson(relation))
          .toList(),
      recommendations: (json['recommendations']['edges'] as List)
          .map((recommendation) => Media.fromRecs(recommendation))
          .toList(),
      nextAiringEpisode: json['nextAiringEpisode'] != null
          ? NextAiringEpisode.fromJson(json['nextAiringEpisode'])
          : null,
      rankings: (json['rankings'] as List)
          .map((ranking) => Ranking.fromJson(ranking))
          .toList(),
      mediaType: type,
      serviceType: ServicesType.anilist,
    );
  }

  factory Media.fromSmallJson(Map<String, dynamic> json, bool isManga,
      {bool isMal = false}) {
    return Media(
      id: (isMal ? json['idMal']?.toString() : json['id'].toString()) ?? '',
      romajiTitle: json['title']['romaji'] ?? '?',
      title: json['title']['english'] ?? json['title']['romaji'] ?? '?',
      description: json['description'] ?? '',
      poster: json['coverImage']?['large'] ?? '?',
      cover: json['bannerImage'],
      rating: ((json['averageScore'] ?? 0) / 10).toStringAsFixed(1),
      type: isManga ? 'MANGA' : 'ANIME',
      mediaType: isManga ? ItemType.manga : ItemType.anime,
      serviceType: ServicesType.anilist,
    );
  }

  factory Media.fromCarouselData(CarouselData data, ItemType type) {
    return Media(
        id: data.id!.toString(),
        romajiTitle: data.title ?? '?',
        title: data.title ?? '?',
        poster: data.poster ?? '?',
        rating: data.extraData ?? '0.0',
        mediaType: type,
        serviceType: data.servicesType);
  }

  factory Media.fromRecs(Map<String, dynamic> json) {
    return Media(
        id: json['node']['mediaRecommendation'] != null
            ? json['node']['mediaRecommendation']['id'].toString()
            : '',
        title: json['node']['mediaRecommendation'] != null
            ? json['node']['mediaRecommendation']['title']['english'] ??
                json['node']['mediaRecommendation']['title']['romaji']
            : '',
        poster: json['node']['mediaRecommendation'] != null
            ? json['node']['mediaRecommendation']['coverImage']['large']
            : '',
        rating: ((json['node']['mediaRecommendation'] != null
                    ? json['node']['mediaRecommendation']['averageScore'] ?? 0
                    : 0) /
                10)
            .toString(),
        serviceType: ServicesType.anilist);
  }

  factory Media.fromOfflineMedia(OfflineMedia offline, ItemType type) {
    return Media(
      id: offline.id?.toString() ?? '0',
      title: offline.name ?? offline.english ?? offline.jname ?? '?',
      romajiTitle: offline.jname ?? '?',
      description: offline.description ?? '?',
      poster: offline.poster ?? '?',
      cover: offline.cover,
      totalEpisodes: offline.totalEpisodes?.toString() ?? '?',
      type: offline.type ?? '?',
      season: offline.season ?? '?',
      premiered: offline.premiered ?? '?',
      duration: offline.duration ?? '?',
      status: offline.status ?? '?',
      rating: offline.rating ?? '?',
      popularity: offline.popularity ?? '?',
      format: offline.format ?? '?',
      aired: offline.aired ?? '?',
      genres: offline.genres ?? const [],
      studios: offline.studios,
      characters: null,
      relations: null,
      recommendations: const [],
      nextAiringEpisode: null,
      rankings: const [],
      mediaType: type,
      serviceType: offline.serviceIndex != null
          ? ServicesType.values[offline.serviceIndex!]
          : ServicesType.anilist,
    );
  }

  static String _parseDateRange(
      Map<String, dynamic>? start, Map<String, dynamic>? end) {
    if (start == null && end == null) return 'Unknown';
    final startDate = _formatDate(start);
    final endDate = _formatDate(end);
    return '$startDate to $endDate';
  }

  static String _formatDate(Map<String, dynamic>? date) {
    if (date == null) return '?';
    return '${date['year'] ?? '?'}-${date['month']?.toString().padLeft(2, '0') ?? '?'}-${date['day']?.toString().padLeft(2, '0') ?? '?'}';
  }
}

class NextAiringEpisode {
  final int airingAt;
  final int timeUntilAiring;
  final int episode;

  NextAiringEpisode({
    required this.airingAt,
    required this.timeUntilAiring,
    required this.episode,
  });

  factory NextAiringEpisode.fromJson(Map<String, dynamic> json) {
    return NextAiringEpisode(
        airingAt: json['airingAt'],
        timeUntilAiring: json['timeUntilAiring'],
        episode: json['episode']);
  }
}

class Ranking {
  final int rank;
  final String type;
  final int year;

  Ranking({required this.rank, required this.type, required this.year});

  factory Ranking.fromJson(Map<String, dynamic> json) {
    return Ranking(
      rank: json['rank'] ?? 0,
      type: json['type'] ?? '?',
      year: json['year'] ?? 0,
    );
  }
}

extension RemoveDupes on List<Media> {
  List<Media> removeDupes() {
    final seen = <String>{};
    return where((media) => seen.add(media.id)).toList();
  }
}

extension RemoveDupesOnTM on List<TrackedMedia> {
  List<TrackedMedia> removeDupes() {
    final seen = <String>{};
    return where((media) => seen.add(media.id!)).toList();
  }
}