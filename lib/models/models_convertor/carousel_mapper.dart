import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:nyantv/models/Anilist/anilist_media_user.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/models/Media/relation.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:nyantv/models/models_convertor/carousel/carousel_data.dart';
import 'package:nyantv/utils/function.dart';

extension DMediaMapper on DMedia {
  CarouselData toCarouselData({
    DataVariant variant = DataVariant.extension,
  }) {
    return CarouselData(
        id: url,
        title: title,
        poster: cover,
        extraData: '??',
        releasing: false,
        servicesType: ServicesType.extensions);
  }
}

extension OfflineMediaMapper on OfflineMedia {
  CarouselData toCarouselData({
    DataVariant variant = DataVariant.offline,
  }) {
    return CarouselData(
        id: id,
        title: name,
        poster: poster,
        source: currentEpisode?.source,
        servicesType: ServicesType.values[serviceIndex ?? 0],
        extraData: (currentEpisode?.number ?? 0).toString(),
        releasing: status == "RELEASING");
  }
}

extension RelationMapper on Relation {
  CarouselData toCarouselData(
      {DataVariant variant = DataVariant.relation}) {
    return CarouselData(
      id: id.toString(),
      title: title,
      poster: poster,
      source: type,
      servicesType: ServicesType.anilist,
      args: type,
      extraData: relationType,
      releasing: status == "RELEASING",
    );
  }
}

extension TrackedMediaMapper on TrackedMedia {
  CarouselData toCarouselData(
      {DataVariant variant = DataVariant.anilist}) {
    return CarouselData(
        id: id.toString(),
        title: title,
        poster: poster,
        servicesType: servicesType,
        extraData: "${episodeCount ?? "??"} | ${releasedEpisodes != null ? releasedEpisodes ?? "??" : totalEpisodes ?? "??"}",
        releasing: mediaStatus == "RELEASING");
  }
}

extension MediaMapper on Media {
  CarouselData toCarouselData(
      {DataVariant variant = DataVariant.regular}) {
    return CarouselData(
        id: id.toString(),
        title: title,
        servicesType: serviceType,
        poster: poster,
        extraData: rating.toString(),
        releasing: status == "RELEASING");
  }
}