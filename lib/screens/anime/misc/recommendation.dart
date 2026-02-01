import 'package:nyantv/ai/animeo.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/screens/anime/details_page.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/animation/slide_scale.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/common/search_bar.dart';
import 'package:nyantv/widgets/header.dart';
import 'package:nyantv/widgets/media_items/media_item.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_progress.dart';
import 'package:get/get.dart';

class AIRecommendation extends StatefulWidget {
  const AIRecommendation({super.key});
  
  @override
  State<AIRecommendation> createState() => _AIRecommendationState();
}

class _AIRecommendationState extends State<AIRecommendation> {
  RxList<Media> recItems = <Media>[].obs;
  final ScrollController _scrollController = ScrollController();
  int currentPage = 1;
  RxBool isAdult = false.obs;
  TextEditingController textEditingController = TextEditingController();
  RxBool isLoading = false.obs;
  RxBool isGrid = false.obs;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    if (serviceHandler.isLoggedIn.value) {
      fetchAiRecommendations(currentPage);
    }
  }

  void _scrollListener() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !isLoading.value) {
      if (textEditingController.text.isEmpty) {
        fetchAiRecommendations(++currentPage);
      } else {
        fetchAiRecommendations(++currentPage,
            username: textEditingController.text);
      }
    }
  }

  Future<void> fetchAiRecommendations(int page, {String? username}) async {
    if (isLoading.value) return;
    isLoading.value = true;

    try {
      final listData = Get.find<ServiceHandler>().animeList;
      final existingIds = listData.map((e) => e.id).toSet();
      final data = await getAiRecommendations(false, page,
          username: username, isAdult: isAdult.value);

      recItems.addAll(data.where((e) => !existingIds.contains(e.id)));
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Glow(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Obx(() {
            return NyantvText(
              text:
                  "AI Picks ${recItems.isNotEmpty ? '(${recItems.length})' : ''}",
              color: Theme.of(context).colorScheme.primary,
            );
          }),
          actions: [
            IconButton(
                onPressed: () {
                  showSettings();
                },
                icon: const Icon(Icons.settings))
          ],
        ),
        body: Obx(() => recItems.isEmpty
            ? !serviceHandler.isLoggedIn.value
                ? _buildInputBox(context)
                : const Center(child: NyantvProgressIndicator())
            : _buildRecommendations(context)),
      ),
    );
  }

  Column _buildInputBox(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: double.infinity),
        SizedBox(
            width: 300,
            child: CustomSearchBar(
              controller: textEditingController,
              onSubmitted: (v) {},
              disableIcons: true,
              hintText: "Enter Username",
            )),
        GestureDetector(
          onTap: () {
            if (textEditingController.text.isNotEmpty) {
              fetchAiRecommendations(1, username: textEditingController.text);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12.multiplyRadius())),
            child: NyantvText(
              text: "Search",
              variant: TextVariant.semiBold,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        )
      ],
    );
  }

  Column _buildRecommendations(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            controller: _scrollController,
            itemCount: recItems.length + 3,
            itemBuilder: (context, index) {
              final isLastRow = index >= recItems.length;
              final lastRowIndex = index - recItems.length;

              if (isLastRow) {
                if (lastRowIndex == 0 || lastRowIndex == 2) {
                  return const SizedBox.shrink();
                } else if (lastRowIndex == 1) {
                  return Obx(() => isLoading.value
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(child: NyantvProgressIndicator()),
                        )
                      : const SizedBox.shrink());
                }
              }

              final data = recItems[index];
              return isGrid.value
                  ? GridAnimeCard(data: data)
                  : _buildRecItem(data);
            },
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: getResponsiveCrossAxisVal(
                MediaQuery.of(context).size.width,
                itemWidth: isGrid.value ? 120 : 400,
              ),
              crossAxisSpacing: 10,
              mainAxisExtent: isGrid.value ? 250 : 200,
            ),
          ),
        ),
      ],
    );
  }

  void showSettings() {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NyantvText(
                  text: "Settings",
                  variant: TextVariant.bold,
                  size: 20,
                ),
                const SizedBox(height: 20),
                Obx(() {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      NyantvText(
                        text: "Grid",
                        variant: TextVariant.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Switch(
                          value: isGrid.value,
                          onChanged: (v) {
                            isGrid.value = v;
                          })
                    ],
                  );
                }),
                Obx(() {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      NyantvText(
                        text: "18+",
                        variant: TextVariant.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Switch(
                          value: isAdult.value,
                          onChanged: (v) {
                            isAdult.value = v;
                          })
                    ],
                  );
                })
              ],
            ),
          );
        });
  }

  Widget _buildRecItem(Media data) {
    return InkWell(
      onTap: () {
        navigate(() => AnimeDetailsPage(media: data, tag: data.description));
      },
      child: SlideAndScaleAnimation(
          child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withOpacity(0.5),
            borderRadius: BorderRadius.circular(12.multiplyRoundness())),
        child: Row(
          children: [
            Hero(
              tag: data.description,
              child: NetworkSizedImage(
                radius: 12.multiplyRoundness(),
                imageUrl: data.poster,
                width: 120,
                height: 170,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NyantvText(
                    text: data.title,
                    variant: TextVariant.semiBold,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Flexible(
                    child: NyantvText(
                      text: data.description,
                      color: Colors.grey[300],
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: data.genres
                        .take(3)
                        .map((e) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius:
                                    BorderRadius.circular(8.multiplyRadius()),
                              ),
                              child: NyantvText(
                                text: e,
                                variant: TextVariant.semiBold,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }
}