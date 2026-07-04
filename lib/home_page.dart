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
    CategoryKind.appCache: (
      title: '应用缓存',
      icon: Icons.apps_rounded,
      accent: Color(0xFF0A84FF),
    ),
    CategoryKind.system: (
      title: '系统垃圾',
      icon: Icons.monitor_rounded,
      accent: Color(0xFF34C759),
    ),
    CategoryKind.developer: (
      title: '开发者垃圾',
      icon: Icons.terminal_rounded,
      accent: Color(0xFFFF9F0A),
    ),
    CategoryKind.review: (
      title: '空间复核',
      icon: Icons.manage_search_rounded,
      accent: Color(0xFF8E8E93),
    ),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Iterable<ScanItem> get _allItems => _controller.allItems;

  Iterable<ScanItem> get _cleanableItems =>
      _allItems.where((i) => i.cleanable && !i.cleaned && i.size > 0);

  int get _cleanableSize => _cleanableItems.fold(0, (sum, i) => sum + i.size);

  int get _scanOnlySize => _allItems.fold(
    0,
    (sum, i) => sum + (!i.cleanable && i.size > 0 ? i.size : 0),
  );

  int get _reviewCount => _allItems.where((i) => !i.cleanable).length;

  int get _higherRiskSelectedCount => _controller.selectedItems
      .where((i) => i.risk == CleanupRisk.medium || i.risk == CleanupRisk.high)
      .length;

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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Row(
          children: [
            _buildSidebar(context),
            Expanded(child: _buildMainPane(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.7);
    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            child: Row(
              children: [
                const _BrandMark(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CleanMac',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        '安全边界清理工具',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              onPressed: _controller.busy ? null : _controller.scan,
              icon: const Icon(Icons.radar_rounded, size: 18),
              label: Text(
                _controller.phase == ScanPhase.idle ? '开始扫描' : '重新扫描',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '扫描范围',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final kind in CategoryKind.values) _buildSidebarTile(kind),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildSafetyPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '安全模式',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '默认只勾选低风险缓存。大型应用数据、模拟器、镜像与归档仅展示占用。',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.35,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_controller.phase == ScanPhase.done ||
              _controller.phase == ScanPhase.cleaning) ...[
            const SizedBox(height: 12),
            _buildTinyStat('扫描总量', formatBytes(_controller.totalSize)),
            const SizedBox(height: 6),
            _buildTinyStat('已选可清理', formatBytes(_controller.selectedSize)),
          ],
        ],
      ),
    );
  }

  Widget _buildTinyStat(String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarTile(CategoryKind kind) {
    final theme = Theme.of(context);
    final meta = _kindMeta[kind]!;
    ScanCategory? category;
    for (final c in _controller.categories) {
      if (c.kind == kind) category = c;
    }
    final selected = _selected == kind;
    final sizeText = category == null ? '未扫描' : formatBytes(category.totalSize);
    final itemCount = category?.items.length ?? 0;
    final accent = meta.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _selected = kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.18)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  meta.icon,
                  color: selected ? accent : theme.colorScheme.onSurfaceVariant,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    Text(
                      itemCount == 0 ? sizeText : '$itemCount 项 · $sizeText',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainPane(BuildContext context) {
    final category = _currentCategory;
    final phase = _controller.phase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCommandBar(context, category),
        if (phase == ScanPhase.sizing) _buildScanProgress(context),
        Expanded(child: _buildBody(context, category)),
      ],
    );
  }

  Widget _buildCommandBar(BuildContext context, ScanCategory? category) {
    final theme = Theme.of(context);
    final meta = _kindMeta[_selected]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: meta.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(meta.icon, color: meta.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.title,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  category?.description ?? '先扫描,再按风险分层处理可清理内容。',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _controller.busy ? null : _controller.scan,
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: Text(
                  _controller.phase == ScanPhase.idle ? '开始扫描' : '重新扫描',
                ),
              ),
              FilledButton.icon(
                onPressed:
                    _controller.phase == ScanPhase.done &&
                        _controller.selectedCount > 0
                    ? _confirmAndClean
                    : null,
                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                label: const Text('清理选中'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanProgress(BuildContext context) {
    final theme = Theme.of(context);
    final value = _controller.totalCount > 0
        ? _controller.scannedCount / _controller.totalCount
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: value, minHeight: 7),
          ),
          const SizedBox(height: 8),
          Text(
            '正在计算目录体积 ${_controller.scannedCount}/${_controller.totalCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ScanCategory? category) {
    final phase = _controller.phase;

    if (phase == ScanPhase.idle) {
      return _buildWelcome(context);
    }

    if (phase == ScanPhase.discovering || phase == ScanPhase.sizing) {
      return _buildScanningState(context);
    }

    return _buildResultsView(context, category);
  }

  Widget _buildWelcome(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 740;
          final intro = _buildWelcomeIntro(context);
          final rules = _buildSafetyRules(context);
          if (compact) {
            return ListView(
              children: [intro, const SizedBox(height: 16), rules],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: intro),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: rules),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWelcomeIntro(BuildContext context) {
    final theme = Theme.of(context);
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _BrandMark(size: 66),
            const SizedBox(height: 22),
            Text(
              '扫描 Mac 上真正占空间的缓存',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '把应用缓存、系统临时文件、开发工具缓存和高占用数据分开展示。默认只选择可重建缓存,高代价内容需要你手动确认。',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _controller.scan,
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text('开始扫描'),
                ),
                _InfoPill(
                  icon: Icons.lock_rounded,
                  label: '白名单删除',
                  color: theme.colorScheme.primary,
                ),
                _InfoPill(
                  icon: Icons.visibility_rounded,
                  label: '大文件先复核',
                  color: const Color(0xFFFF9F0A),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyRules(BuildContext context) {
    final theme = Theme.of(context);
    final rules = [
      (
        icon: Icons.check_circle_rounded,
        title: '默认安全',
        text: '低风险缓存可自动勾选,系统与应用核心数据不会进入删除队列。',
      ),
      (
        icon: Icons.tune_rounded,
        title: '按风险分层',
        text: '中高风险项保留说明,需要你主动勾选后才会清理。',
      ),
      (
        icon: Icons.folder_open_rounded,
        title: '可追溯',
        text: '每一项都能打开所在目录,清理前能看到真实路径。',
      ),
      (
        icon: Icons.search_rounded,
        title: '复核区',
        text: '模拟器、Docker、归档和大体积应用数据只展示占用,不直接删除。',
      ),
    ];
    return _Surface(
      tint: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.22),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '清理策略',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            for (final rule in rules) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(rule.icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rule.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (rule != rules.last) const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanningState(BuildContext context) {
    final theme = Theme.of(context);
    final sizing = _controller.phase == ScanPhase.sizing;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _Surface(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 54,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    value: sizing && _controller.totalCount > 0
                        ? _controller.scannedCount / _controller.totalCount
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  sizing ? '正在计算目录体积' : '正在识别扫描目标',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sizing
                      ? '已扫描 ${_controller.scannedCount}/${_controller.totalCount} 个位置'
                      : '正在汇总应用缓存、系统缓存和开发工具目录。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsView(BuildContext context, ScanCategory? category) {
    if (category == null) {
      return _buildEmptyState(context, '还没有扫描结果');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOverviewMetrics(context),
        _buildCategoryToolbar(context, category),
        Expanded(
          child: category.items.isEmpty
              ? _buildEmptyState(context, '该分类下没有发现可处理内容')
              : category.kind == CategoryKind.appCache
              ? _buildGroupedList(context, category)
              : _buildFlatList(context, category),
        ),
      ],
    );
  }

  Widget _buildOverviewMetrics(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 780;
          final itemWidth = wide
              ? (constraints.maxWidth - 36) / 4
              : (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(
                width: itemWidth,
                label: '扫描总量',
                value: formatBytes(_controller.totalSize),
                icon: Icons.pie_chart_rounded,
                color: theme.colorScheme.primary,
              ),
              _MetricTile(
                width: itemWidth,
                label: '可安全清理',
                value: formatBytes(_cleanableSize),
                icon: Icons.verified_rounded,
                color: const Color(0xFF34C759),
              ),
              _MetricTile(
                width: itemWidth,
                label: '已选中',
                value: formatBytes(_controller.selectedSize),
                icon: Icons.task_alt_rounded,
                color: const Color(0xFF5856D6),
                footnote: '${_controller.selectedCount} 项',
              ),
              _MetricTile(
                width: itemWidth,
                label: '仅复核',
                value: formatBytes(_scanOnlySize),
                icon: Icons.visibility_rounded,
                color: const Color(0xFFFF9F0A),
                footnote: '$_reviewCount 项',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryToolbar(BuildContext context, ScanCategory category) {
    final theme = Theme.of(context);
    final selectable = category.items
        .where((i) => i.cleanable && !i.cleaned && i.size > 0)
        .toList();
    final allChecked =
        selectable.isNotEmpty && selectable.every((i) => i.checked);
    final anyChecked = selectable.any((i) => i.checked);
    final selectedCount = category.items
        .where((i) => i.cleanable && i.checked && !i.cleaned && i.size > 0)
        .length;
    final scanOnlyCount = category.items.where((i) => !i.cleanable).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
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
            const SizedBox(width: 4),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '本类 ${category.items.length} 项',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _InfoPill(
                    icon: Icons.cleaning_services_rounded,
                    label: '可清理 ${selectable.length}',
                    color: const Color(0xFF34C759),
                  ),
                  if (scanOnlyCount > 0)
                    _InfoPill(
                      icon: Icons.visibility_rounded,
                      label: '仅复核 $scanOnlyCount',
                      color: const Color(0xFFFF9F0A),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '已选 $selectedCount 项 · ${formatBytes(category.selectedSize)}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _higherRiskSelectedCount > 0
                    ? const Color(0xFFD35400)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatList(BuildContext context, ScanCategory category) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: category.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _buildItemTile(context, category.items[index]),
    );
  }

  Widget _buildGroupedList(BuildContext context, ScanCategory category) {
    final groups = _controller.appCacheGroupsFor(category);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildGroupTile(context, groups[index]),
    );
  }

  Widget _buildGroupTile(BuildContext context, AppCacheGroup group) {
    final theme = Theme.of(context);
    final expanded = _expandedGroups.contains(group.key);
    final selectable = group.items
        .where((i) => i.cleanable && !i.cleaned && i.size > 0)
        .toList();
    final allChecked =
        selectable.isNotEmpty && selectable.every((i) => i.checked);
    final anyChecked = selectable.any((i) => i.checked);
    final highestRisk = _highestRisk(group.items);

    return _ResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (!_expandedGroups.remove(group.key)) {
                _expandedGroups.add(group.key);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
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
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (group.cleaned)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: _StatePill(
                                  label: '已清理',
                                  icon: Icons.check_rounded,
                                  color: Color(0xFF34C759),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          group.items.length == 1
                              ? group.primaryItem.path
                              : '${group.items.length} 个缓存位置 · ${group.cleanableItems.length} 个可清理',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _RiskPill(risk: highestRisk),
                            if (!group.hasCleanableContent)
                              const _StatePill(
                                label: '仅复核',
                                icon: Icons.visibility_rounded,
                                color: Color(0xFFFF9F0A),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 92,
                    child: Text(
                      group.items.any((i) => i.size < 0)
                          ? '扫描中'
                          : formatBytes(group.totalSize),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '打开缓存目录',
                    icon: const Icon(Icons.folder_open_rounded, size: 19),
                    onPressed: () => _openDirectory(group.primaryItem.path),
                  ),
                  IconButton(
                    tooltip: group.hasCleanableContent
                        ? '清理该应用的缓存'
                        : '仅展示占用,不支持直接清理',
                    icon: const Icon(Icons.cleaning_services_rounded, size: 19),
                    color: group.cleaned || !group.hasCleanableContent
                        ? null
                        : theme.colorScheme.primary,
                    onPressed:
                        _controller.busy ||
                            group.cleaned ||
                            !group.hasCleanableContent
                        ? null
                        : () => _confirmAndCleanGroup(group),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest.withValues(
                  alpha: 0.65,
                ),
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
              child: Column(
                children: [
                  for (final item in group.items) _buildGroupSubTile(item),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupSubTile(ScanItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(58, 8, 12, 8),
      child: Row(
        children: [
          Checkbox(
            value: item.cleanable ? item.checked : false,
            onChanged:
                !item.cleanable ||
                    item.cleaned ||
                    _controller.busy ||
                    item.size <= 0
                ? null
                : (v) => setState(() => item.checked = v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.path,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (item.note != null)
                  Text(
                    item.note!,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD35400),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _RiskPill(risk: item.risk),
          const SizedBox(width: 10),
          SizedBox(
            width: 82,
            child: Text(
              item.size < 0 ? '扫描中' : formatBytes(item.size),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: '打开目录',
            icon: const Icon(Icons.folder_open_rounded, size: 17),
            onPressed: () => _openDirectory(item.path),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, ScanItem item) {
    final theme = Theme.of(context);
    return _ResultSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          children: [
            Checkbox(
              value: item.cleanable ? item.checked : false,
              onChanged:
                  !item.cleanable ||
                      item.cleaned ||
                      _controller.busy ||
                      item.size <= 0
                  ? null
                  : (v) => setState(() => item.checked = v ?? false),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _riskColor(item.risk).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _riskIcon(item.risk),
                size: 19,
                color: _riskColor(item.risk),
              ),
            ),
            const SizedBox(width: 12),
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
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (item.cleaned)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: _StatePill(
                            label: '已清理',
                            icon: Icons.check_rounded,
                            color: Color(0xFF34C759),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.path,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!item.cleanable || item.note != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      !item.cleanable ? '仅展示占用,请使用对应工具清理' : item.note!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: !item.cleanable
                            ? const Color(0xFF4B5F73)
                            : const Color(0xFFD35400),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _RiskPill(risk: item.risk),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(
                item.size < 0 ? '扫描中' : formatBytes(item.size),
                textAlign: TextAlign.right,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '打开目录',
              icon: const Icon(Icons.folder_open_rounded, size: 19),
              onPressed: () => _openDirectory(item.path),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 52,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  CleanupRisk _highestRisk(Iterable<ScanItem> items) {
    var highest = CleanupRisk.low;
    for (final item in items) {
      if (_riskRank(item.risk) > _riskRank(highest)) highest = item.risk;
    }
    return highest;
  }

  int _riskRank(CleanupRisk risk) {
    switch (risk) {
      case CleanupRisk.low:
        return 0;
      case CleanupRisk.medium:
        return 1;
      case CleanupRisk.high:
        return 2;
      case CleanupRisk.scanOnly:
        return 3;
    }
  }
}

IconData _riskIcon(CleanupRisk risk) {
  switch (risk) {
    case CleanupRisk.low:
      return Icons.verified_rounded;
    case CleanupRisk.medium:
      return Icons.hourglass_bottom_rounded;
    case CleanupRisk.high:
      return Icons.warning_amber_rounded;
    case CleanupRisk.scanOnly:
      return Icons.visibility_rounded;
  }
}

Color _riskColor(CleanupRisk risk) {
  switch (risk) {
    case CleanupRisk.low:
      return const Color(0xFF34C759);
    case CleanupRisk.medium:
      return const Color(0xFFFF9F0A);
    case CleanupRisk.high:
      return const Color(0xFFFF453A);
    case CleanupRisk.scanOnly:
      return const Color(0xFF4B5F73);
  }
}

String _riskLabel(CleanupRisk risk) {
  switch (risk) {
    case CleanupRisk.low:
      return '低风险';
    case CleanupRisk.medium:
      return '可重建';
    case CleanupRisk.high:
      return '高代价';
    case CleanupRisk.scanOnly:
      return '仅复核';
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tint ?? theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ResultSurface extends StatelessWidget {
  const _ResultSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.footnote,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Container(
        height: 78,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (footnote != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          footnote!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.risk});

  final CleanupRisk risk;

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(risk);
    return _StatePill(
      label: _riskLabel(risk),
      icon: _riskIcon(risk),
      color: color,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _StatePill(label: label, icon: icon, color: color);
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26E0C2), Color(0xFF0A84FF), Color(0xFF0B3D91)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A84FF).withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        Icons.verified_user_rounded,
        color: Colors.white,
        size: size * 0.56,
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
      return _IconImage(data: cached);
    }
    return FutureBuilder<Uint8List?>(
      future: AppIconService.iconFor(path),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.folder_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return _IconImage(data: data);
      },
    );
  }
}

class _IconImage extends StatelessWidget {
  const _IconImage({required this.data});

  final Uint8List data;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(data, width: 34, height: 34, gaplessPlayback: true),
    );
  }
}
