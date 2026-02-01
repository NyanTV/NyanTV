import 'package:nyantv/controllers/service_handler/params.dart';
import 'package:nyantv/models/Anilist/anilist_media_user.dart';
import 'package:nyantv/models/Anilist/anilist_profile.dart';
import 'package:get/get.dart';

abstract class OnlineService {
  RxList<TrackedMedia> get animeList;
  Rx<TrackedMedia> get currentMedia;
  RxBool get isLoggedIn;
  Rx<Profile> get profileData;

  Future<void> autoLogin();
  Future<void> login();
  Future<void> logout();
  Future<void> refresh();
  void setCurrentMedia(String id, {bool isManga = false});
  Future<void> updateListEntry(UpdateListEntryParams params);
  Future<void> deleteListEntry(String listId, {bool isAnime = true});
}
