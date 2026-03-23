import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';

class Extensions {
  final settings = Get.put(SourceController());

  Future<void> addRepo(ItemType type, String repo, String managerId) async {
    final em = Get.find<ExtensionManager>();

    await em.addRepo(repo, type, managerId);
  }

  Future<void> addRepos(
      ItemType type, List<String> repos, String managerId) async {
    final em = Get.find<ExtensionManager>();

    await em.addRepos(repos, type, managerId);
  }
}
