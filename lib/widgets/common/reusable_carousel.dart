import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/models/models_convertor/carousel/carousel_data.dart';
import 'package:nyantv/screens/anime/details_page.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/animation/slide_scale.dart';
import 'package:nyantv/widgets/common/cards/base_card.dart';
import 'package:nyantv/widgets/common/cards/card_gate.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_progress.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ReusableCarousel extends StatefulWidget {
  final List<dynamic> data;
  final String title;
  final ItemType type;
  final DataVariant variant;
  final bool isLoading;
  final Source? source;
  final CardStyle? cardStyle;

  const ReusableCarousel({
    super.key,
    required this.data,
    required this.title,
    this.type = ItemType.anime,
    this.variant = DataVariant.regular,
    this.isLoading = false,
    this.source,
    this.cardStyle,
  });

  @override
  State<ReusableCarousel> createState() => _ReusableCarouselState();
}

class _ReusableCarouselState extends State<ReusableCarousel> {
  @override
  Widget build(BuildContext context) {
    if (_isEmptyOrOffline) {
      return _buildOfflinePlaceholder();
    }

    if (widget.data.isEmpty && !widget.isLoading) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderTitle(),
          const SizedBox(height: 10),
          widget.isLoading
              ? const Center(child: NyantvProgressIndicator())
              : _buildCarouselList(),
        ],
      ),
    );
  }

  // Computed properties
  bool get _isEmptyOrOffline =>
      widget.data.isEmpty && widget.variant == DataVariant.offline;

  // Header title section
  Widget _buildHeaderTitle() {
    return Padding(
      padding: const EdgeInsets.only(left: 20.0),
      child: Text(
        widget.title,
        style: TextStyle(
          fontFamily: "Poppins-SemiBold",
          fontSize: 17,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  // Offline placeholder display
  Widget _buildOfflinePlaceholder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        _buildHeaderTitle(),
        const SizedBox(height: 15, width: double.infinity),
        SizedBox(
          height: 280,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.movie_filter_rounded),
              const SizedBox(height: 10, width: double.infinity),
              NyantvText(
                text: "Lowkey time for a binge sesh 🎬",
                variant: TextVariant.semiBold,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Main carousel list builder
  Widget _buildCarouselList() {
    final List<CarouselData> processedData =
        convertData(widget.data, variant: widget.variant);

    return Obx(() {
      return SizedBox(
        height: getCardHeight(CardStyle.values[settingsController.cardStyle],
            getPlatform(context)),
        child: SuperListView.builder(
          itemCount: processedData.length,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 15, top: 5, bottom: 10),
          itemBuilder: (context, index) =>
              _buildCarouselItem(processedData[index], index),
        ),
      );
    });
  }

  Widget _buildCarouselItem(CarouselData itemData, int index) {
    final tag = '${itemData.hashCode}-${itemData.id}';

    return Obx(() {
      final child = NyantvOnTap(
        onTap: () => _navigateToDetailsPage(itemData, tag),
        child: settingsController.enableAnimation
            ? SlideAndScaleAnimation(child: _buildCard(itemData, tag))
            : _buildCard(itemData, tag),
      );
      return child;
    });
  }

  MediaCardGate _buildCard(CarouselData itemData, String tag) {
    return MediaCardGate(
        itemData: itemData,
        tag: tag,
        variant: widget.variant,
        type: widget.type,
        cardStyle: CardStyle.values[settingsController.cardStyle]);
  }

  void _navigateToDetailsPage(CarouselData itemData, String tag) {
    final controller = Get.find<SourceController>();
    final ItemType mediaType = ItemType.anime;
    final media = Media.fromCarouselData(itemData, mediaType);

    final Widget page = AnimeDetailsPage(
      media: media,
      tag: tag,
    );
    _setActiveSource(controller, itemData);
    navigate(() => page);
  }

  void _setActiveSource(SourceController controller, CarouselData itemData) {
    if (widget.source != null) {
      controller.setActiveSource(widget.source!);
    } else if (itemData.source != null) {
      controller.getExtensionByName(itemData.source!);
    }
  }
}