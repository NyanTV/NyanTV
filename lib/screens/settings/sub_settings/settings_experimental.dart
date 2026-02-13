import 'package:nyantv/utils/logger.dart';

import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/utils/shaders.dart';
import 'package:nyantv/widgets/common/custom_tiles.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_dropdown.dart';
import 'package:nyantv/widgets/custom_widgets/custom_expansion_tile.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/utils/device_ram.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

class SettingsExperimental extends StatefulWidget {
  const SettingsExperimental({super.key});

  @override
  State<SettingsExperimental> createState() => _SettingsExperimentalState();
}

class _SettingsExperimentalState extends State<SettingsExperimental>
    with TickerProviderStateMixin {
  final settings = Get.find<Settings>();
  final _detectedRamMB = 0.obs;
  final _recommendedProfile = BufferProfile.medium.obs;

  final _shadersDownloaded = false.obs;
  final _isDownloading = false.obs;
  final _downloadProgress = 0.0.obs;
  final _currentStatus = ''.obs;
  final _enableShaders = false.obs;
  final _autoIdleMinutes = 0.obs;
  final FocusNode _bufferProfileFocusNode = FocusNode();
  final GlobalKey _bufferProfileDropdownKey = GlobalKey();

  final _cacheDays = 7.obs;

  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkShadersAvailability();
    _detectDeviceRam();
    getSavedSettings();
    _bufferProfileFocusNode.addListener(() => setState(() {}));
  }

  void _detectDeviceRam() {
    _detectedRamMB.value = DeviceRamHelper.getDeviceRamMB();
    _recommendedProfile.value = DeviceRamHelper.getRecommendedProfile();
  }

  void getSavedSettings() {
    _enableShaders.value =
        settings.preferences.get('shaders_enabled', defaultValue: false);
    _cacheDays.value = settings.preferences.get('cache_days', defaultValue: 7);
    _autoIdleMinutes.value = settings.autoIdleMinutes;
  }

  void saveSettings() {
    settings.preferences.put('shaders_enabled', _enableShaders.value);
    settings.preferences.put('cache_days', _cacheDays.value);
    settings.autoIdleMinutes = _autoIdleMinutes.value;
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  Future<void> _checkShadersAvailability() async {
    try {
      final shadersPath = PlayerShaders.getShaderBasePath();
      final shadersDir = Directory(shadersPath);

      if (await shadersDir.exists()) {
        final files = await shadersDir.list().toList();
        _shadersDownloaded.value = files.isNotEmpty;
      }
    } catch (e) {
      print('Error checking shaders: $e');
    }
  }

  Future<void> _downloadShaders() async {
    _isDownloading.value = true;
    _downloadProgress.value = 0.0;
    _currentStatus.value = 'Initializing download...';

    try {
      await _updateStatus('Connecting to server...', 0.05);
      await Future.delayed(const Duration(milliseconds: 500));

      final shadersPath = PlayerShaders.getShaderBasePath();
      final mpvPath = Directory(shadersPath).path;

      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/anime4k_shaders.zip';
      final tempFile = File(tempFilePath);

      await _updateStatus('Downloading shaders...', 0.1);

      final dio = Dio();
      await dio.download(
        'https://github.com/NyanTV/NyanTV/raw/refs/heads/main/assets/shaders/shaders_new.zip',
        tempFilePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = 0.1 + (received / total) * 0.6;
            _updateStatus('Downloading shaders...', progress);
          }
        },
      );

      await _updateStatus('Download complete, extracting...', 0.75);
      await Future.delayed(const Duration(milliseconds: 500));

      final bytes = await tempFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      await _updateStatus('Extracting shader files...', 0.8);

      for (final file in archive) {
        if (file.isFile) {
          final outFile = File('$mpvPath${file.name}');
          Logger.i('Path is: ${outFile.path}');

          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      await _updateStatus('Finalizing installation...', 0.98);
      await Future.delayed(const Duration(milliseconds: 300));

      await _updateStatus('Installation complete!', 1.0);

      _isDownloading.value = false;
      _shadersDownloaded.value = true;
      _currentStatus.value = 'Shaders installed successfully!';
    } catch (e) {
      _isDownloading.value = false;
      _currentStatus.value = 'Download failed: $e';

      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/anime4k_shaders.zip');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (cleanupError) {
        print('Cleanup error: $cleanupError');
      }
    }
  }

  Future<void> _updateStatus(String status, double progress) async {
    _currentStatus.value = status;
    _downloadProgress.value = progress;
    _progressController.animateTo(progress);
  }

  Widget _buildBufferDetail(BuildContext context, BufferProfile profile) {
    final config = DeviceRamHelper.getConfig(profile);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailRow(
          context,
          'Buffer Size',
          '${config.bufferMB}MB',
        ),
        _buildDetailRow(
          context,
          'Cache Duration',
          '${config.cacheSecs}s',
        ),
        _buildDetailRow(
          context,
          'Max Skip',
          '~${config.cacheSecs - 10}s',
        ),
      ],
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeybindingItem(String key, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              key,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _bufferProfileFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Glow(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          child: Padding(
            padding: getResponsiveValue(context,
                mobileValue: const EdgeInsets.fromLTRB(10.0, 50.0, 10.0, 20.0),
                desktopValue:
                    const EdgeInsets.fromLTRB(25.0, 50.0, 25.0, 20.0)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  IconButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainer
                          .withValues(alpha: 0.5),
                    ),
                    onPressed: () {
                      Get.back();
                    },
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const SizedBox(width: 10),
                  const Text("Experimental Settings",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
              const SizedBox(height: 30),
              Obx(() => NyantvExpansionTile(
                    title: "Reader",
                    initialExpanded: true,
                    content: Column(
                      children: [
                        CustomSliderTile(
                            icon: Icons.extension,
                            title: "Cache Duration",
                            label: "${_cacheDays.value} days",
                            description:
                                "When should the image cache be cleared?",
                            sliderValue: _cacheDays.value.toDouble(),
                            divisions: 30,
                            onChanged: (double value) {
                              _cacheDays.value = value.toInt();
                              saveSettings();
                            },
                            max: 30)
                      ],
                    ),
                  )),
              Obx(() => NyantvExpansionTile(
                title: "Auto Idle",
                initialExpanded: false,
                content: Column(
                  children: [
                    CustomSliderTile(
                      icon: Iconsax.timer_1,
                      title: "Auto Idle Timer",
                      description: "Automatically start NyanDVD after inactivity",
                      sliderValue: _autoIdleMinutes.value.toDouble(),
                      divisions: 20,
                      onChanged: (double value) {
                        _autoIdleMinutes.value = value.toInt();
                        saveSettings();
                      },
                      min: 0,
                      max: 20,
                      showOffWhenZero: true,
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Time in minutes",
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )),

              GetBuilder<Settings>(
                builder: (settings) {
                  return NyantvExpansionTile(
                    title: "UI Scaling",
                    initialExpanded: true,
                    content: Column(
                      children: [
                        CustomSliderTile(
                          icon: Icons.zoom_in_outlined,
                          title: "UI Scale Factor",
                          label: "${(settings.uiScale * 100).toInt()}%",
                          description:
                              "Adjust the overall UI scale (like browser zoom)",
                          sliderValue: settings.uiScale,
                          divisions: 15,
                          onChanged: (double value) {
                            settings.uiScale = value;
                          },
                          min: 0.5,
                          max: 2.0,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Tip: 0.5 (50%) = Smaller, 1 (100%) = Default, 1.5 (150%) = Larger",
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              Obx(() {
                final currentProfile = settings.tvBufferProfile.value;

                return NyantvExpansionTile(
                  title: "TV Player Buffer",
                  initialExpanded: false,
                  content: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.memory,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pick Your Buffer Profile',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Choosing more than available MIGHT crash the player!',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.tune,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Buffer Profile',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            Focus(
                              focusNode: _bufferProfileFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.select ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.enter) {
                                    final ctx = _bufferProfileDropdownKey
                                        .currentContext;
                                    if (ctx != null) {
                                      final RenderBox box = ctx
                                          .findRenderObject() as RenderBox;
                                      final Offset pos = box.localToGlobal(
                                          box.size.center(Offset.zero));
                                      GestureBinding.instance
                                          .handlePointerEvent(
                                              PointerDownEvent(position: pos));
                                      Future.delayed(
                                          const Duration(milliseconds: 50),
                                          () {
                                        GestureBinding.instance
                                            .handlePointerEvent(
                                                PointerUpEvent(position: pos));
                                      });
                                    }
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: _bufferProfileFocusNode.hasFocus
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 2,
                                        )
                                      : Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.3),
                                          width: 1,
                                        ),
                                ),
                                child: NyantvDropdown(
                                  key: _bufferProfileDropdownKey,
                                  items: BufferProfile.values.map((profile) {
                                    return DropdownItem(
                                      text: DeviceRamHelper.getProfileName(
                                          profile),
                                      value: DeviceRamHelper.profileToString(
                                          profile),
                                    );
                                  }).toList(),
                                  selectedItem: DropdownItem(
                                    text: DeviceRamHelper.getProfileName(
                                        currentProfile),
                                    value: DeviceRamHelper.profileToString(
                                        currentProfile),
                                  ),
                                  label: "SELECT BUFFER PROFILE",
                                  icon: Icons.memory,
                                  onChanged: (item) {
                                    final profile =
                                        DeviceRamHelper.stringToProfile(
                                            item.value);
                                    settings.saveTVBufferProfile(profile);
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DeviceRamHelper.getProfileDescription(
                                        currentProfile),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (currentProfile !=
                                      BufferProfile.medium) ...[
                                    const SizedBox(height: 8),
                                    _buildBufferDetail(context, currentProfile),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Higher buffer = better skip performance but uses more RAM. '
                                'Only affects Android TV devices.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              Obx(() {
                settings.animationDuration;
                return NyantvExpansionTile(
                  title: 'Player',
                  initialExpanded: true,
                  content: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Iconsax.eye,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Anime 4K Enhancement',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    Text(
                                      'Real-time 4K upscaling for anime content',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Obx(
                            () {
                              return Column(
                                children: [
                                  if (_isDownloading.value) ...[
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.3),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              AnimatedBuilder(
                                                animation: _pulseAnimation,
                                                builder: (context, child) {
                                                  return Transform.scale(
                                                    scale: _pulseAnimation.value,
                                                    child: Icon(
                                                      Iconsax.document_download,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      size: 16,
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _currentStatus.value,
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${(_downloadProgress * 100).toInt()}%',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          LinearProgressIndicator(
                                            value: _downloadProgress.value,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withValues(alpha: 0.2),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else if (_shadersDownloaded.value) ...[
                                    Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.3),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Iconsax.play,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Enable Shaders',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                      ),
                                                    ),
                                                    Text(
                                                      getResponsiveValue(
                                                          context,
                                                          mobileValue:
                                                              'if Enabled the Shaders will be applied to the player through hdr menu',
                                                          desktopValue:
                                                              'if Enabled the Shaders will be applied to the player through keybindings'),
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: 0.7),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Obx(() {
                                                return Switch(
                                                  value: _enableShaders.value,
                                                  onChanged: (value) {
                                                    _enableShaders.value = value;
                                                    saveSettings();
                                                  },
                                                );
                                              })
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.3),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Iconsax.play,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Choose Shader Profile',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurface,
                                                          ),
                                                        ),
                                                        Text(
                                                          'Choose accordingly to your system specs.\nMid End = Eg. GTX 980, GTX 1060, RX 570\nHigh End = Eg. GTX 1080, RTX 2070, RTX 3060, RX 590, Vega 56',
                                                          style: TextStyle(
                                                            color:
                                                                Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurface
                                                                    .withValues(
                                                                        alpha:
                                                                            0.7),
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Obx(() {
                                                List<String> availProfiles = [
                                                  'MID-END',
                                                  'HIGH-END'
                                                ];

                                                return Container(
                                                  margin: const EdgeInsets.only(
                                                      top: 20.0),
                                                  child: NyantvDropdown(
                                                      items: availProfiles
                                                          .map((e) => DropdownItem(
                                                              text: e, value: e))
                                                          .toList(),
                                                      selectedItem: DropdownItem(
                                                          text: settingsController
                                                              .selectedProfile,
                                                          value: settingsController
                                                              .selectedProfile),
                                                      label: "SELECT PROFILE",
                                                      icon: Iconsax.play,
                                                      onChanged: (e) =>
                                                          settingsController
                                                                  .selectedProfile =
                                                              e.text),
                                                );
                                              })
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        AnimatedContainer(
                                          width: _enableShaders.value ? null : 0,
                                          curve: Curves.easeInOut,
                                          height:
                                              _enableShaders.value ? null : 0,
                                          duration:
                                              const Duration(milliseconds: 300),
                                          padding: EdgeInsets.all(
                                              _enableShaders.value ? 16 : 0),
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .errorContainer
                                                .withValues(alpha: 0.3),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Iconsax.info_circle,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Warning',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                      ),
                                                    ),
                                                    Text(
                                                      getResponsiveValue(
                                                          context,
                                                          mobileValue:
                                                              'you might get black screen or it may not work.',
                                                          desktopValue:
                                                              'will lag like hell on older gpus'),
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onErrorContainer
                                                            .withValues(
                                                                alpha: 0.7),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        getResponsiveValue(
                                          context,
                                          mobileValue: const SizedBox.shrink(),
                                          strictMode: true,
                                          desktopValue: Obx(() {
                                            return AnimatedOpacity(
                                              opacity:
                                                  _enableShaders.value ? 1 : 0.3,
                                              duration: const Duration(
                                                  milliseconds: 300),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withValues(alpha: 0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Iconsax.keyboard,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .primary,
                                                          size: 20,
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                'Shader Profiles Initialized',
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .onSurface,
                                                                ),
                                                              ),
                                                              Text(
                                                                'Use keyboard shortcuts during playback to switch profiles',
                                                                style: TextStyle(
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withValues(
                                                                          alpha:
                                                                              0.7),
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      'Available Keybindings:',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    _buildKeybindingItem(
                                                        'CTRL + 1',
                                                        'Anime4K: Mode A (Fast)'),
                                                    _buildKeybindingItem(
                                                        'CTRL + 2',
                                                        'Anime4K: Mode B (Fast)'),
                                                    _buildKeybindingItem(
                                                        'CTRL + 3',
                                                        'Anime4K: Mode C (Fast)'),
                                                    _buildKeybindingItem(
                                                        'CTRL + 4',
                                                        'Anime4K: Mode A+A (Fast)'),
                                                    _buildKeybindingItem(
                                                        'CTRL + 5',
                                                        'Anime4K: Mode B+B (Fast)'),
                                                    _buildKeybindingItem(
                                                        'CTRL + 6',
                                                        'Anime4K: Mode C+A (Fast)'),
                                                    _buildKeybindingItem(
                                                        'CTRL + 0',
                                                        'Reset (Clear Shaders)'),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ),
                                      ],
                                    )
                                  ] else ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _downloadShaders,
                                        icon: const Icon(
                                            Iconsax.document_download),
                                        label:
                                            const Text('Download 4K Shaders'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.9),
                                          foregroundColor: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Download size: ~4MB',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                        fontSize: 11,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              );
                            },
                          )
                        ],
                      )),
                );
              }),
            ]),
          ),
        ),
      ),
    );
  }

}