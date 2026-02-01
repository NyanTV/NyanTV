import 'dart:io';

import 'package:nyantv/utils/extensions.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';

class Deeplink {
  static void handleDeepLink(Uri uri) {
    if (uri.host != 'add-repo') return;
    ExtensionType extType;
    String? repoUrl;

    if (Platform.isAndroid) {
      switch (uri.scheme.toLowerCase()) {
        case 'aniyomi':
          extType = ExtensionType.aniyomi;
          repoUrl = uri.queryParameters["url"]?.trim();
          break;
        case 'tachiyomi':
          extType = ExtensionType.aniyomi;
          repoUrl = uri.queryParameters["url"]?.trim();
          break;
        default:
          extType = ExtensionType.mangayomi;
          repoUrl = (uri.queryParameters["url"])?.trim();
      }
    } else {
      extType = ExtensionType.mangayomi;
      repoUrl = (uri.queryParameters["url"])?.trim();
    }

    if (repoUrl != null) {
      Extensions().addRepo(ItemType.anime, repoUrl, extType);
    }

    if (repoUrl != null) {
      snackBar("Added Repo Link Successfully!");
    } else {
      snackBar("Missing required parameters in the link.");
    }
  }
}