import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/screens/extensions/ExtensionScreen.dart';
import 'package:nyantv/screens/profile/profile_page.dart';
import 'package:nyantv/screens/settings/settings.dart';
import 'package:nyantv/screens/local_source/local_source_view.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_bottomsheet.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:iconly/iconly.dart';
import 'package:iconsax/iconsax.dart';

class SettingsSheet extends StatelessWidget {
  SettingsSheet({super.key});

  final serviceHandler = Get.find<ServiceHandler>();

  static void show(BuildContext context) {
    NyantvSheet(
      customWidget: SettingsSheet(),
    ).show(context);
  }

  void showServiceSelector(BuildContext context) {
    final services = [
      {
        'type': ServicesType.anilist,
        'name': "AniList",
        'icon': 'anilist-icon.png',
      },
      if (serviceHandler.extensionService.installedExtensions.length > 2)
        {
          'type': ServicesType.extensions,
          'name': "Extensions",
          'icon': null,
        },
    ];

    NyantvSheet.custom(
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NyantvText(
                text: "Select Service",
                size: 16,
                variant: TextVariant.semiBold,
              ),
              ...services.map((service) => ListTile(
                    leading: service['icon'] != null
                        ? Image.asset(
                            color: Theme.of(context).colorScheme.primary,
                            'assets/images/${service['icon']}',
                            width: 30,
                          )
                        : Icon(
                            Icons.extension,
                            size: 30,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    title: NyantvText(
                      text: service['name'] as String,
                      variant: TextVariant.semiBold,
                      color: serviceHandler.serviceType.value == service['type']
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onTap: () {
                      serviceHandler
                          .changeService(service['type'] as ServicesType);
                      Get.back();
                    },
                  )),
            ],
          ),
        ),
        context);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const SizedBox(width: 5),
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                child: serviceHandler.isLoggedIn.value
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: CachedNetworkImage(
                            fit: BoxFit.cover,
                            width: 45,
                            height: 45,
                            errorWidget: (context, url, error) =>
                                const Icon(IconlyBold.profile),
                            imageUrl:
                                serviceHandler.profileData.value.avatar ?? ''),
                      )
                    : Icon(
                        Icons.person,
                        color: Theme.of(context).colorScheme.inverseSurface,
                      ),
              ),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(serviceHandler.profileData.value.name ?? 'Guest'),
                  if (serviceHandler.serviceType.value !=
                      ServicesType.extensions)
                    NyantvOnTap(
                      onTap: () {
                        if (serviceHandler.isLoggedIn.value) {
                          serviceHandler.logout();
                        } else {
                          serviceHandler.login();
                        }
                        Get.back();
                      },
                      child: Text(
                        serviceHandler.isLoggedIn.value ? 'Logout' : 'Login',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const Expanded(
                child: SizedBox.shrink(),
              ),
              NyantvOnTap(
                child: IconButton(
                    onPressed: () {
                      snackBar('This feature is not available yet.');
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    icon: const Icon(Iconsax.notification)),
              )
            ]),
            const SizedBox(height: 10),
            if (serviceHandler.isLoggedIn.value &&
                serviceHandler.serviceType.value == ServicesType.anilist)
              NyantvOnTap(
                child: ListTile(
                  leading: const Icon(Iconsax.user),
                  title: const Text('View Profile'),
                  onTap: () {
                    Get.back();
                    navigate(() => const ProfilePage());
                  },
                ),
              ),
            Obx(() {
              final shouldShowExts =
                  sourceController.shouldShowExtensions.value;
              return isMobile && shouldShowExts
                  ? ListTile(
                      leading: const Icon(Icons.extension),
                      title: const Text('Extensions'),
                      onTap: () {
                        Get.back();
                        navigate(() => const ExtensionScreen());
                      },
                    )
                  : const SizedBox.shrink();
            }),
            NyantvOnTap(
              child: ListTile(
                leading: const Icon(HugeIcons.strokeRoundedAiSetting),
                title: const Text('Change Service'),
                onTap: () {
                  Get.back();
                  showServiceSelector(context);
                },
              ),
            ),
            NyantvOnTap(
              child: ListTile(
                leading: const Icon(Iconsax.document_download),
                title: const Text('Local Media'),
                onTap: () {
                  Get.back();
                  navigate(() => const WatchOffline());
                },
              ),
            ),
            NyantvOnTap(
              child: ListTile(
                leading: const Icon(Iconsax.setting),
                title: const Text('Settings'),
                onTap: () {
                  Get.back();
                  navigate(() => const SettingsPage());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}