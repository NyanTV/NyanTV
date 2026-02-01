// ignore_for_file: prefer_const_constructors

import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/screens/home_page.dart';
import 'package:nyantv/screens/search/search_view.dart';
import 'package:nyantv/utils/fallback/fallback_anime.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AnimeStats extends StatelessWidget {
  final Media data;
  final String countdown;
  const AnimeStats({
    super.key,
    required this.data,
    required this.countdown,
  });

  @override
  Widget build(BuildContext context) {
    final serviceHandler = Get.find<ServiceHandler>();
    final covers = [
                ...serviceHandler.anilistService.trendingAnimes,
              ]
        .where((e) => e.cover != null && (e.cover?.isNotEmpty ?? false))
        .toList();
    final isDesktop = MediaQuery.of(context).size.width > 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (countdown != '0')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  NyantvText(
                    text:
                        "EPISODE ${data.nextAiringEpisode?.episode} WILL BE RELEASED IN",
                    size: 14,
                    variant: TextVariant.bold,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.8),
                  ),
                  const SizedBox(height: 5),
                  NyantvText(
                    text: countdown,
                    size: getResponsiveSize(context,
                        mobileSize: 16, desktopSize: 20),
                    variant: TextVariant.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        const NyantvText(
          text: "Statistics",
          variant: TextVariant.bold,
          size: 17,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Column(
            children: [
              StateItem(label: "Type", value: data.type),
              StateItem(label: "Rating", value: '${data.rating}/10'),
              StateItem(label: "Popularity", value: data.popularity),
              StateItem(label: "Season", value: data.season),
              StateItem(label: "Format", value: data.format),
              StateItem(label: "Status", value: data.status),
              StateItem(label: "Duration", value: data.duration),
              StateItem(label: "Total Episodes", value: data.totalEpisodes),
              StateItem(label: "Premiered", value: data.premiered),
              if (data.studios?.isNotEmpty ?? false)
                StateItem(label: "Studios", value: data.studios?.first ?? ''),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const NyantvText(
          text: "Romaji Title",
          variant: TextVariant.bold,
          size: 17,
        ),
        10.height(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: NyantvText(
            text: data.romajiTitle,
            variant: TextVariant.semiBold,
            size: 14,
            color: Colors.grey[300],
          ),
        ),
        const SizedBox(height: 30),
        const NyantvText(
          text: "Synopsis",
          variant: TextVariant.bold,
          size: 17,
        ),
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: NyantvText(
            text: data.description,
            size: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
            maxLines: 100,
            stripHtml: true,
          ),
        ),
        const SizedBox(height: 10),
        const NyantvText(
          text: "Genres",
          variant: TextVariant.bold,
          size: 17,
        ),
        GridView.builder(
          padding: EdgeInsets.only(top: 15),
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: data.genres.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: getResponsiveCrossAxisCount(context,
                  baseColumns: 2, maxColumns: 4),
              mainAxisSpacing: 10,
              mainAxisExtent: isDesktop ? 80 : 60,
              crossAxisSpacing: 10),
          itemBuilder: (context, index) {
            final e = data.genres[index];
            return ImageButton(
                buttonText: e,
                height: 80,
                onPressed: () {
                  if (serviceHandler.serviceType.value ==
                      ServicesType.anilist) {
                    navigate(() => SearchPage(
                          searchTerm: '',
                          initialFilters: {
                            'genres': [e]
                          },
                        ));
                  }
                },
                backgroundImage: covers[index].cover!);
          },
        ),
      ],
    );
  }
}

class StateItem extends StatelessWidget {
  final String label;
  final String value;
  const StateItem({
    super.key,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NyantvText(
            text: label,
            variant: TextVariant.semiBold,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: NyantvText(
              text: value,
              variant: TextVariant.semiBold,
              color: Theme.of(context).colorScheme.primary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
