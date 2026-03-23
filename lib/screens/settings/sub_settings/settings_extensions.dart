import 'dart:io';
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

  Extension get _manager => em.managers[_managerIndex];

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
              child: _buildManagerBar(theme),
            ),
          Expanded(child: _buildBody()),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddDialog,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add Repo',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          backgroundColor: theme.primary,
          foregroundColor: theme.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
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
          const Text("Extensions",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildManagerBar(ColorScheme colors) {
    final managers = em.managers;
    final total = managers.length;
    final alignX = total > 1 ? -1.0 + (2.0 * _managerIndex / (total - 1)) : 0.0;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withOpacity(0.1)),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuint,
          alignment: Alignment(alignX, 0),
          child: FractionallySizedBox(
            widthFactor: 1 / total,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Row(
          children: managers.asMap().entries.map((e) {
            final selected = _managerIndex == e.key;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!selected) {
                    HapticFeedback.lightImpact();
                    setState(() => _managerIndex = e.key);
                  }
                },
                child: AnimatedOpacity(
                  opacity: selected ? 1.0 : 0.6,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
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
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildBody() {
    return Obx(() {
      final repos = _manager.getReposRx(ItemType.anime).value;
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: repos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final repo = repos[i];
        return _buildRepoCard(repo, isDeleting: _deleting[repo.url] == true);
      },
    );
  }

  Widget _buildRepoCard(Repo repo, {required bool isDeleting}) {
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

    return AnimatedOpacity(
      opacity: isDeleting ? 0.4 : 1.0,
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
                  ]),
            ),
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: repo.url));
                snackBar('URL copied');
              },
              icon: Icon(Icons.copy_outlined,
                  size: 18, color: colors.onSurfaceVariant),
            ),
            if (isDeleting)
              Padding(
                padding: const EdgeInsets.all(9),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.error)),
              )
            else
              IconButton(
                onPressed: () => _removeRepo(repo),
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: colors.error),
              ),
          ]),
        ),
      ),
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
          TextField(
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
