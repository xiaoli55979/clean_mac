import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_icon_service.dart';
import 'models.dart';
import 'scan_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScanController _controller = ScanController();
  CategoryKind _selected = CategoryKind.appCache;
  final Set<String> _expandedGroups = {};

  static const _kindMeta = {
    CategoryKind.appCache: (title: '应用缓存', icon: Icons.apps),
    CategoryKind.system: (title: '系统垃圾', icon: Icons.desktop_mac_outlined),
    CategoryKind.developer: (title: '开发者垃圾', icon: Icons.code),
    CategoryKind.review: (title: '空间复核', icon: Icons.manage_search),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ScanCategory? get _currentCategory {
    for (final c in _controller.categories) {
      if (c.kind == _selected) return c;
    }
    return null;
  }

  Future<void> _confirmAndClean() async {
    final items = _controller.selectedItems.toList();
    final count = items.length;
    final size = _controller.selectedSize;
    final warningLines = items
        .where((i) => i.risk != CleanupRisk.low || i.note != null)
        .take(5)
        .map((i) => '- ${i.title}: ${i.note ?? _riskText(i.risk)}')
        .toList();
    final message = StringBuffer('将删除选中的 $count 项,共 ${formatBytes(size)}。');
    if (warningLines.isNotEmpty) {
      message
        ..writeln()
        ..writeln()
        ..writeln('需要注意:')
        ..writeAll(warningLines, '\n');
    }
    message
      ..writeln()
      ..writeln()
      ..write('缓存删除后应用会自动重建,确定继续?');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理'),
        content: Text(message.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final summary = await _controller.cleanSelected();
    if (!mounted) return;
    _showCleanResult(summary);
  }

  String _riskText(CleanupRisk risk) {
    switch (risk) {
      case CleanupRisk.low:
        return '低风险缓存';
      case CleanupRisk.medium:
        return '可重建,但首次使用会变慢';
      case CleanupRisk.high:
        return '高代价清理项,请确认后手动勾选';
      case CleanupRisk.scanOnly:
        return '仅展示占用,不支持直接清理';
    }
  }

  Future<void> _confirmAndCleanGroup(AppCacheGroup group) async {
    final items = group.cleanableItems
        .where((i) => !i.cleaned && i.size > 0)
        .toList();
    if (items.isEmpty) return;
    final size = items.fold<int>(0, (sum, i) => sum + i.size);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理'),
        content: Text(
          '将删除「${group.name}」的 ${items.length} 个可清理缓存位置,'
          '共 ${formatBytes(size)}。\n\n确定继续?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final summary = await _controller.cleanGroup(group);
    if (!mounted) return;
    _showCleanResult(summary, name: group.name);
  }

  void _showCleanResult(CleanSummary summary, {String? name}) {
    final target = name == null ? '' : '「$name」';
    final message = summary.failedCount > 0
        ? '已清理$target,释放 ${formatBytes(summary.freed)},${summary.failedCount} 项未能完全清理(可能被占用或无权限)'
        : '已清理$target,释放 ${formatBytes(summary.freed)}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 目录直接在访达中打开,单个文件则定位到它
  void _openDirectory(String path) {
    final isDir =
        FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.directory;
    Process.run('open', isDir ? [path] : ['-R', path]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Row(
          children: [
            _buildSidebar(context),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _buildMainPane(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              children: [
                Icon(
                  Icons.cleaning_services,
                  color: theme.colorScheme.primary,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CleanMac',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final kind in CategoryKind.values) _buildSidebarTile(kind),
          const Spacer(),
          if (_controller.phase == ScanPhase.done ||
              _controller.phase == ScanPhase.cleaning)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('扫描总计', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        formatBytes(_controller.totalSize),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(CategoryKind kind) {
    final meta = _kindMeta[kind]!;
    ScanCategory? category;
    for (final c in _controller.categories) {
      if (c.kind == kind) category = c;
    }
    final sizeText = category == null ? '' : formatBytes(category.totalSize);
    return ListTile(
      selected: _selected == kind,
      leading: Icon(meta.icon),
      title: Text(meta.title),
      trailing: Text(sizeText, style: const TextStyle(fontSize: 12)),
      onTap: () => setState(() => _selected = kind),
    );
  }

  Widget _buildMainPane(BuildContext context) {
    final theme = Theme.of(context);
    final category = _currentCategory;
    final phase = _controller.phase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kindMeta[_selected]!.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (category != null)
                      Text(
                        category.description,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _controller.busy ? null : _controller.scan,
                icon: const Icon(Icons.radar, size: 18),
                label: Text(phase == ScanPhase.idle ? '开始扫描' : '重新扫描'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed:
                    phase == ScanPhase.done && _controller.selectedCount > 0
                    ? _confirmAndClean
                    : null,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: Text('清理选中项 (${formatBytes(_controller.selectedSize)})'),
              ),
            ],
          ),
        ),
        if (phase == ScanPhase.sizing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _controller.totalCount > 0
                      ? _controller.scannedCount / _controller.totalCount
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  '正在扫描 ${_controller.scannedCount}/${_controller.totalCount}…',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        Expanded(child: _buildBody(context, category)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ScanCategory? category) {
    final theme = Theme.of(context);
    final phase = _controller.phase;

    if (phase == ScanPhase.idle) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cleaning_services_outlined,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text('扫描 Mac 上的缓存与垃圾文件', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('包括各应用缓存、系统日志以及开发工具产生的垃圾', style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _controller.scan,
              icon: const Icon(Icons.radar),
              label: const Text('开始扫描'),
            ),
          ],
        ),
      );
    }

    if (phase == ScanPhase.discovering) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在分析已安装应用与扫描目标…'),
          ],
        ),
      );
    }

    if (category == null || category.items.isEmpty) {
      return const Center(child: Text('该分类下没有发现可清理的内容'));
    }

    if (category.kind == CategoryKind.appCache) {
      return _buildGroupedList(context, category);
    }
    return _buildFlatList(context, category);
  }

  Widget _buildSelectAllBar(
    BuildContext context,
    ScanCategory category, {
    required String countText,
  }) {
    final theme = Theme.of(context);
    final selectable = category.items
        .where((i) => i.cleanable && !i.cleaned)
        .toList();
    final allChecked =
        selectable.isNotEmpty && selectable.every((i) => i.checked);
    final anyChecked = selectable.any((i) => i.checked);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: allChecked ? true : (anyChecked ? null : false),
            onChanged: _controller.busy || selectable.isEmpty
                ? null
                : (_) => setState(() {
                    final target = !allChecked;
                    for (final i in selectable) {
                      i.checked = target;
                    }
                  }),
          ),
          Text(countText, style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(
            '已选 ${category.items.where((i) => i.cleanable && i.checked).length} 项 · ${formatBytes(category.selectedSize)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildFlatList(BuildContext context, ScanCategory category) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelectAllBar(
          context,
          category,
          countText: '共 ${category.items.length} 项',
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: category.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
            itemBuilder: (context, index) =>
                _buildItemTile(context, category.items[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupedList(BuildContext context, ScanCategory category) {
    final groups = _controller.appCacheGroupsFor(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelectAllBar(
          context,
          category,
          countText: '共 ${groups.length} 个应用 · ${category.items.length} 个缓存位置',
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) =>
                _buildGroupTile(context, groups[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupTile(BuildContext context, AppCacheGroup group) {
    final theme = Theme.of(context);
    final expanded = _expandedGroups.contains(group.key);
    final selectable = group.items
        .where((i) => i.cleanable && !i.cleaned)
        .toList();
    final allChecked =
        selectable.isNotEmpty && selectable.every((i) => i.checked);
    final anyChecked = selectable.any((i) => i.checked);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (!_expandedGroups.remove(group.key)) {
              _expandedGroups.add(group.key);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: allChecked ? true : (anyChecked ? null : false),
                  onChanged: selectable.isEmpty || _controller.busy
                      ? null
                      : (_) => setState(() {
                          final target = !allChecked;
                          for (final i in selectable) {
                            i.checked = target;
                          }
                        }),
                ),
                const SizedBox(width: 4),
                _AppIcon(path: group.appPath ?? group.primaryItem.path),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              group.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          if (group.cleaned)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '已清理',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        group.items.length == 1
                            ? group.primaryItem.path
                            : '${group.items.length} 个缓存位置',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  group.items.any((i) => i.size < 0)
                      ? '扫描中…'
                      : formatBytes(group.totalSize),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: '打开缓存目录',
                  icon: const Icon(Icons.folder_open, size: 18),
                  onPressed: () => _openDirectory(group.primaryItem.path),
                ),
                IconButton(
                  tooltip: group.hasCleanableContent
                      ? '清理该应用的缓存'
                      : '仅展示占用,不支持直接清理',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: group.cleaned || !group.hasCleanableContent
                        ? null
                        : theme.colorScheme.error,
                  ),
                  onPressed:
                      _controller.busy ||
                          group.cleaned ||
                          !group.hasCleanableContent
                      ? null
                      : () => _confirmAndCleanGroup(group),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.hintColor,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final item in group.items) _buildGroupSubTile(context, item),
      ],
    );
  }

  Widget _buildGroupSubTile(BuildContext context, ScanItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 64, right: 24),
      child: Row(
        children: [
          Checkbox(
            value: item.cleanable ? item.checked : false,
            onChanged: !item.cleanable || item.cleaned || _controller.busy
                ? null
                : (v) => setState(() => item.checked = v ?? false),
          ),
          Expanded(
            child: Text(
              item.path,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.size < 0 ? '扫描中…' : formatBytes(item.size),
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            tooltip: '打开目录',
            icon: const Icon(Icons.folder_open, size: 16),
            onPressed: () => _openDirectory(item.path),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, ScanItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        children: [
          Checkbox(
            value: item.cleanable ? item.checked : false,
            onChanged: !item.cleanable || item.cleaned || _controller.busy
                ? null
                : (v) => setState(() => item.checked = v ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    if (item.cleaned)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '已清理',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  item.path,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: 11,
                  ),
                ),
                if (!item.cleanable)
                  Text(
                    '仅展示占用,请使用对应工具清理',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blueGrey.shade700,
                    ),
                  ),
                if (item.note != null)
                  Text(
                    item.note!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.size < 0 ? '扫描中…' : formatBytes(item.size),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            tooltip: '打开目录',
            icon: const Icon(Icons.folder_open, size: 18),
            onPressed: () => _openDirectory(item.path),
          ),
        ],
      ),
    );
  }
}

/// 异步加载并缓存路径对应的系统图标
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final cached = AppIconService.cached(path);
    if (cached != null) {
      return Image.memory(cached, width: 30, height: 30, gaplessPlayback: true);
    }
    return FutureBuilder<Uint8List?>(
      future: AppIconService.iconFor(path),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return Icon(
            Icons.folder,
            size: 30,
            color: Theme.of(context).hintColor,
          );
        }
        return Image.memory(data, width: 30, height: 30, gaplessPlayback: true);
      },
    );
  }
}
