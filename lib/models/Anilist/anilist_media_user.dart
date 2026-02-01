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
}