import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';

class Extensions {
  final settings = Get.put(SourceController());

  Future<void> addRepo(ItemType type, String repo, ExtensionType ext) async {
    settings.setAnimeRepo(repo, ext);
    await settings.fetchRepos();
  }
}