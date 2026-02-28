import 'package:nyantv/controllers/service_handler/service_handler.dart';

class TrackedMedia {
  String? id;
  String? title;
  String? poster;
  String? episodeCount;
  String? chapterCount;
  String? rating;
  String? totalEpisodes;
  String? releasedEpisodes;
  String? watchingStatus;
  String? format;
  String? mediaStatus;
  String? score;
  String? type;
  String? mediaListId;
  ServicesType servicesType;

  TrackedMedia(
      {this.id,
      this.title,
      this.poster,
      this.episodeCount,
      this.chapterCount,
      this.rating,
      this.totalEpisodes,
      this.releasedEpisodes,
      this.watchingStatus,
      this.format,
      this.mediaStatus,
      this.score,
      this.type,
      this.mediaListId,
      this.servicesType = ServicesType.anilist});

  factory TrackedMedia.fromJson(Map<String, dynamic> json) {
    return TrackedMedia(
        id: json['media']['id']?.toString(),
        title: json['media']['title']['english'] ??
            json['media']['title']['romaji'] ??
            json['media']['title']['native'],
        poster: json['media']['coverImage']['large'],
        episodeCount: json['progress']?.toString(),
        chapterCount: json['media']['chapters']?.toString(),
        totalEpisodes: json['media']['episodes']?.toString(),
        releasedEpisodes: json['media']['nextAiringEpisode'] != null
            ? (json['media']['nextAiringEpisode']['episode'] - 1).toString()
            : null,
        rating: (double.tryParse(
                    json['media']['averageScore']?.toString() ?? "0")! /
                10)
            .toString(),
        watchingStatus: json['status'],
        format: json['media']['format'],
        mediaStatus: json['media']['status'],
        score: json['score']?.toString(),
        type: json['media']['type']?.toString(),
        servicesType: ServicesType.anilist,
        mediaListId:
            (json['media']['mediaListEntry']['id'] ?? json['media']['id'])
                .toString());
  }

  factory TrackedMedia.fromMAL(Map<String, dynamic> json) {
    return TrackedMedia(
      id: json['node']['id']?.toString(),
      title: json['node']['title'],
      servicesType: ServicesType.mal,
      poster: json['node']['main_picture']['large'],
      chapterCount:
          json['node']?['list_status']?['num_chapters_read']?.toString() ?? '?',
      episodeCount: json['list_status']?['num_chapters_read']?.toString() ??
          json['list_status']?['num_episodes_watched']?.toString() ??
          '?',
      totalEpisodes: json['node']?['num_episodes']?.toString() ??
          json['node']?['num_chapters']?.toString() ??
          '?',
      rating: json['node']?['mean']?.toString() ?? '?',
      watchingStatus: returnConvertedStatus(json['list_status']['status']),
      score: json['list_status']['score']?.toString(),
      type: null,
      mediaListId: json['node']['id']?.toString(),
    );
  }
}

String getAniListStatusEquivalent(String status) {
  switch (status.toLowerCase()) {
    case 'watching':
      return 'CURRENT';
    case 'completed':
      return 'COMPLETED';
    case 'on_hold':
      return 'PAUSED';
    case 'dropped':
      return 'DROPPED';
    case 'plan_to_watch':
      return 'PLANNING';
    default:
      return 'UNKNOWN';
  }
}

String returnConvertedStatus(String status) {
  switch (status) {
    case 'watching':
    case 'reading':
      return 'CURRENT';
    case 'completed':
      return 'COMPLETED';
    case 'on_hold':
      return 'PAUSED';
    case 'dropped':
      return 'DROPPED';
    case 'plan_to_watch':
    case 'plan_to_read':
      return 'PLANNING';
    default:
      return 'ALL';
  }
}

String getMALStatusEquivalent(String status, {bool isAnime = true}) {
  switch (status.toUpperCase()) {
    case 'CURRENT':
      return isAnime ? 'watching' : 'reading';
    case 'COMPLETED':
      return 'completed';
    case 'PAUSED':
      return 'on_hold';
    case 'DROPPED':
      return 'dropped';
    case 'PLANNING':
      return isAnime ? 'plan_to_watch' : 'plan_to_read';
    default:
      return 'unknown';
  }
}