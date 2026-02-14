import 'dart:io';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/screens/settings/sub_settings/widgets/repo_dialog.dart';
import 'package:nyantv/widgets/common/custom_tiles.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/custom_widgets/custom_expansion_tile.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:flutter/material.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsExtensions extends StatefulWidget {
  const SettingsExtensions({super.key});

  @override
  State<SettingsExtensions> createState() => _SettingsExtensionsState();
}

class _SettingsExtensionsState extends State<SettingsExtensions> {
  final settings = Get.find<Settings>();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Glow(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: getResponsiveValue(context,
                mobileValue: const EdgeInsets.fromLTRB(10.0, 50.0, 10.0, 20.0),
                desktopValue:
                    const EdgeInsets.fromLTRB(25.0, 50.0, 25.0, 20.0)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withOpacity(0.5),
                      ),
                      onPressed: () {
                        Get.back();
                      },
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    const SizedBox(width: 10),
                    const Text("Extensions",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 30),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NyantvExpansionTile(
                        initialExpanded: true,
                        title: 'Mangayomi',
                        content: Column(
                          children: [
                            CustomTile(
                              icon: HugeIcons.strokeRoundedGithub,
                              title: 'Github Repo',
                              description: "Add github repo anime",
                              onTap: () => const GitHubRepoDialog(
                                type: ItemType.anime,
                                extType: ExtensionType.mangayomi,
                              ).show(context: context),
                            ),
                          ],
                        )),
                    if (Platform.isAndroid)
                      NyantvExpansionTile(
                          initialExpanded: true,
                          title: 'Aniyomi',
                          content: Column(
                            children: [
                              CustomTile(
                                icon: HugeIcons.strokeRoundedGithub,
                                title: 'Github Repo',
                                description: "Add github repo for anime",
                                onTap: () => const GitHubRepoDialog(
                                  type: ItemType.anime,
                                  extType: ExtensionType.aniyomi,
                                ).show(context: context),
                              ),
                            ],
                          )),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}