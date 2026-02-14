import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/widgets/header.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class GradientPoster extends StatelessWidget {
  const GradientPoster({
    super.key,
    required this.tag,
    required this.data,
    required this.posterUrl,
  });

  final Media? data;
  final String posterUrl;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          height: isDesktop ? 460 : 400,
          child: Obx(() {
            return NetworkSizedImage(
              imageUrl: data?.cover ?? posterUrl,
              errorImage: data?.poster,
              radius: 0,
              height: 300,
              width: double.infinity,
              color: settingsController.liquidMode
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                  : null,
            );
          }),
        ),
        Container(
          height: isDesktop ? 460 : 400,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.0),
                Colors.black.withOpacity(0.2),
                Theme.of(context).colorScheme.surface.withOpacity(0.95),
                Theme.of(context).colorScheme.surface,
              ],
              stops: const [0.0, 0.4, 0.8, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20.0, bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Stack(children: [
                Hero(
                  tag: tag,
                  child: NetworkSizedImage(
                      imageUrl: posterUrl,
                      radius: 16.multiplyRoundness(),
                      width: isDesktop ? 150 : 120,
                      height: isDesktop ? 200 : 180),
                ),
                if (data?.isAdult ?? false)
                  Positioned(
                    bottom: 7,
                    right: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: const Text(
                        '18+',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: "Poppins-Bold",
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width / 2,
                    child: Text(data?.title ?? 'Loading...',
                        style: const TextStyle(
                            fontFamily: "Poppins-Bold", fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Text(data?.status ?? "Ongoing? Idk",
                        style: TextStyle(
                            fontFamily: "Poppins-Bold",
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary)),
                  )
                ],
              )
            ],
          ),
        ),
        Positioned(
            top: 30,
            right: 20,
            child: NyantvOnTap(
              onTap: () {
                Get.back();
              },
              margin: 0,
              child: IconButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainer,
                  ),
                  onPressed: () {
                    Get.back();
                  },
                  icon: const Icon(Icons.close)),
            )),
      ],
    );
  }
}