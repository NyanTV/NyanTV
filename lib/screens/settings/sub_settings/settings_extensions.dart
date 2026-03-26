import 'package:nyantv/utils/tv_text_field.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class SettingsExtensions extends StatefulWidget {
  const SettingsExtensions({super.key});

  @override
  State<SettingsExtensions> createState() => _SettingsExtensionsState();
}

class _SettingsExtensionsState extends State<SettingsExtensions> {
  final em = Get.find<ExtensionManager>();

  int _managerIndex = 0;
  final Map<String, bool> _deleting = {};
  final List<FocusNode> _managerFocusNodes = [];
  final FocusNode _fabFocusNode = FocusNode();

  final List<FocusNode> _repoCopyNodes = [];
  final List<FocusNode> _repoDeleteNodes = [];

  Extension get _manager => em.managers[_managerIndex];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < em.managers.length; i++) {
      _managerFocusNodes.add(FocusNode());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_managerFocusNodes.isNotEmpty) {
        _managerFocusNodes[_managerIndex].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final n in _managerFocusNodes) {
      n.dispose();
    }
    _fabFocusNode.dispose();
    for (final n in _repoCopyNodes) {
      n.dispose();
    }
    for (final n in _repoDeleteNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _rebuildRepoFocusNodes(int count) {
    for (final n in _repoCopyNodes) {
      n.dispose();
    }
    for (final n in _repoDeleteNodes) {
      n.dispose();
    }
    _repoCopyNodes.clear();
    _repoDeleteNodes.clear();
    for (int i = 0; i < count; i++) {
      _repoCopyNodes.add(FocusNode());
      _repoDeleteNodes.add(FocusNode());
    }
  }

  Future<void> _addRepos(List<String> urls) async {
    await em.addRepos(urls, ItemType.anime, _manager.id);
  }

  Future<void> _removeRepo(Repo repo) async {
    final key = repo.url;
    setState(() => _deleting[key] = true);
    try {
      await em.removeRepo(repo, ItemType.anime);
    } catch (_) {
      snackBar('Failed to remove repo');
    } finally {
      if (mounted) setState(() => _deleting.remove(key));
    }
  }

  void _openAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddRepoDialog(
        onAdd: (urls) async {
          await _addRepos(urls);
          if (mounted) {
            snackBar('${urls.length} repo${urls.length > 1 ? 's' : ''} added');
          }
        },
      ),
    );
  }

  KeyEventResult _handleManagerKey(
      RawKeyEvent event, int index, int total, List<Repo> repos) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      HapticFeedback.lightImpact();
      setState(() => _managerIndex = index);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (repos.isNotEmpty && _repoCopyNodes.isNotEmpty) {
        _repoCopyNodes[0].requestFocus();
      } else {
        _fabFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        index == total - 1) {
      _fabFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCopyKey(
      RawKeyEvent event, int index, List<Repo> repos, Repo repo) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      Clipboard.setData(ClipboardData(text: repo.url));
      snackBar('URL copied');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _repoDeleteNodes[index].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_managerFocusNodes.isNotEmpty) {
        _managerFocusNodes[_managerIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _repoCopyNodes[index - 1].requestFocus();
      } else if (_managerFocusNodes.isNotEmpty) {
        _managerFocusNodes[_managerIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < repos.length - 1) {
        _repoCopyNodes[index + 1].requestFocus();
      } else {
        _fabFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleDeleteKey(
      RawKeyEvent event, int index, List<Repo> repos, Repo repo) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _removeRepo(repo);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _repoCopyNodes[index].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _repoDeleteNodes[index - 1].requestFocus();
      } else if (_managerFocusNodes.isNotEmpty) {
        _managerFocusNodes[_managerIndex].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < repos.length - 1) {
        _repoDeleteNodes[index + 1].requestFocus();
      } else {
        _fabFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    if (em.managers.isEmpty) {
      return Glow(
        child: Scaffold(
          body: Column(children: [
            _buildHeader(),
            const Expanded(
              child: Center(child: Text('No extension managers found.')),
            ),
          ]),
        ),
      );
    }

    return Glow(
      child: Scaffold(
        body: Column(children: [
          _buildHeader(),
          if (em.managers.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Obx(() {
                final repos = _manager.getReposRx(ItemType.anime).value;
                return _buildManagerBar(theme, repos);
              }),
            ),
          Expanded(child: _buildBody()),
        ]),
        floatingActionButton: Builder(builder: (context) {
          return Focus(
            focusNode: _fabFocusNode,
            onFocusChange: (_) => setState(() {}),
            onKey: (node, event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  if (_repoCopyNodes.isNotEmpty) {
                    _repoCopyNodes.last.requestFocus();
                  } else if (_managerFocusNodes.isNotEmpty) {
                    _managerFocusNodes[_managerIndex].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (_managerFocusNodes.isNotEmpty) {
                    _managerFocusNodes[_managerIndex].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  _openAddDialog();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Builder(builder: (context) {
              final hasFocus = Focus.of(context).hasFocus;
              final theme = Theme.of(context).colorScheme;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: hasFocus
                      ? Border.all(color: theme.secondary, width: 2)
                      : Border.all(color: Colors.transparent, width: 2),
                ),
                child: FloatingActionButton.extended(
                  focusNode: FocusNode(canRequestFocus: false),
                  onPressed: _openAddDialog,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Repo',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  backgroundColor: theme.primary,
                  foregroundColor: theme.onPrimary,
                  focusColor: Colors.transparent,
                  focusElevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              );
            }),
          );
        }),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 50, 10, 10),
      child: Row(
        children: [
          IconButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainer
                  .withOpacity(0.5),
            ),
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          const SizedBox(width: 10),
          const Text('Extensions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildManagerBar(ColorScheme colors, List<Repo> repos) {
    final managers = em.managers;

    return SizedBox(
      height: 46,
      child: Row(
        children: managers.asMap().entries.map((e) {
          final selected = _managerIndex == e.key;
          final focusNode = e.key < _managerFocusNodes.length
              ? _managerFocusNodes[e.key]
              : FocusNode();

          return Expanded(
            child: Focus(
              focusNode: focusNode,
              onFocusChange: (_) => setState(() {}),
              onKey: (node, event) =>
                  _handleManagerKey(event, e.key, managers.length, repos),
              child: Builder(builder: (context) {
                final hasFocus = Focus.of(context).hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.secondary
                        : hasFocus
                            ? colors.secondary.withOpacity(0.15)
                            : colors.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: hasFocus
                        ? Border.all(
                            color:
                                selected ? colors.onSecondary : colors.primary,
                            width: 2,
                          )
                        : Border.all(color: colors.outline.withOpacity(0.1)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      splashColor: colors.secondary.withOpacity(0.2),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _managerIndex = e.key);
                      },
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.extension_outlined,
                                size: 14,
                                color: selected
                                    ? colors.onSecondary
                                    : colors.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                e.value.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: selected
                                      ? colors.onSecondary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    return Obx(() {
      final repos = _manager.getReposRx(ItemType.anime).value;

      if (repos.length != _repoCopyNodes.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _rebuildRepoFocusNodes(repos.length));
          }
        });
      }

      if (repos.isEmpty) return _buildEmpty();
      return _buildRepoList(repos);
    });
  }

  Widget _buildEmpty() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              color: colors.surfaceContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(20)),
          child: Icon(Icons.storage_outlined,
              size: 30, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text('No repositories yet',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
        const SizedBox(height: 5),
        Text('Tap + to add a repository URL',
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
      ]),
    );
  }

  Widget _buildRepoList(List<Repo> repos) {
    if (_repoCopyNodes.length != repos.length) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: repos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final repo = repos[i];
        final colors = Theme.of(context).colorScheme;
        String? host;
        String path;
        try {
          final uri = Uri.parse(repo.url);
          host = uri.host.isEmpty ? null : uri.host;
          path = uri.path.isEmpty ? repo.url : uri.path;
        } catch (_) {
          path = repo.url;
        }

        final copyHasFocus = _repoCopyNodes[i].hasFocus;
        final deleteHasFocus = _repoDeleteNodes[i].hasFocus;

        return AnimatedOpacity(
          opacity: _deleting[repo.url] == true ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow.withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.storage_outlined,
                      size: 17, color: colors.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(path,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'monospace',
                              color: colors.onSurface,
                              fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (host != null) ...[
                        const SizedBox(height: 2),
                        Text(host,
                            style: TextStyle(
                                fontSize: 11, color: colors.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                // Copy
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: copyHasFocus
                      ? BoxDecoration(
                          border: Border.all(color: colors.secondary, width: 2),
                          borderRadius: BorderRadius.circular(8))
                      : null,
                  child: Focus(
                    focusNode: _repoCopyNodes[i],
                    onFocusChange: (_) => setState(() {}),
                    onKey: (node, event) =>
                        _handleCopyKey(event, i, repos, repo),
                    child: IconButton(
                      focusNode: FocusNode(canRequestFocus: false),
                      focusColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: repo.url));
                        snackBar('URL copied');
                      },
                      icon: Icon(Icons.copy_outlined,
                          size: 18, color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
                // Delete
                if (_deleting[repo.url] == true)
                  Padding(
                    padding: const EdgeInsets.all(9),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.error)),
                  )
                else
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: deleteHasFocus
                        ? BoxDecoration(
                            border:
                                Border.all(color: colors.secondary, width: 2),
                            borderRadius: BorderRadius.circular(8))
                        : null,
                    child: Focus(
                      focusNode: _repoDeleteNodes[i],
                      onFocusChange: (_) => setState(() {}),
                      onKey: (node, event) =>
                          _handleDeleteKey(event, i, repos, repo),
                      child: IconButton(
                        focusNode: FocusNode(canRequestFocus: false),
                        focusColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: () => _removeRepo(repo),
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: colors.error),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _AddRepoDialog extends StatefulWidget {
  final Future<void> Function(List<String>) onAdd;
  const _AddRepoDialog({required this.onAdd});

  @override
  State<_AddRepoDialog> createState() => _AddRepoDialogState();
}

class _AddRepoDialogState extends State<_AddRepoDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final urls = _ctrl.text
        .trim()
        .split(RegExp(r'[\n,]'))
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;

    setState(() => _loading = true);
    try {
      await widget.onAdd(urls);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: c.primaryContainer,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.storage_outlined,
                  size: 18, color: c.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Add Repository',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface)),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_rounded,
                  size: 20, color: c.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 18),
          TvTextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 2,
            minLines: 1,
            style: TextStyle(
                fontSize: 12.5, fontFamily: 'monospace', color: c.onSurface),
            decoration: InputDecoration(
              hintText: 'https://raw.githubusercontent.com/...',
              hintStyle: TextStyle(
                  fontSize: 12, color: c.onSurfaceVariant.withOpacity(0.6)),
              contentPadding: const EdgeInsets.all(14),
              filled: true,
              fillColor: c.surfaceContainer,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.primary))
                  : ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Repository'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: c.onPrimary,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ),
          ]),
        ]),
      ),
    );
  }
}
