// lib/models/Offline/Hive/offline_storage.dart
import 'package:nyantv/models/Offline/Hive/custom_list.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:hive/hive.dart';

part 'offline_storage.g.dart';

@HiveType(typeId: 8)
class OfflineStorage extends HiveObject {
  @HiveField(0)
  List<OfflineMedia>? animeLibrary;

  @HiveField(1)
  List<CustomList>? animeCustomList;

  OfflineStorage(
      {this.animeLibrary = const <OfflineMedia>[],
      this.animeCustomList});
}
