/// 垃圾类别
enum CategoryKind { appCache, system, developer, review }

/// 清理风险等级;scanOnly 只展示占用,不参与删除。
enum CleanupRisk { low, medium, high, scanOnly }

class ScanCategory {
  ScanCategory({
    required this.kind,
    required this.title,
    required this.description,
    required this.items,
  });

  final CategoryKind kind;
  final String title;
  final String description;
  final List<ScanItem> items;

  int get totalSize =>
      items.fold(0, (sum, i) => sum + (i.size > 0 ? i.size : 0));

  int get selectedSize => items.fold(
    0,
    (sum, i) => sum + (i.cleanable && i.checked && i.size > 0 ? i.size : 0),
  );
}

class ScanItem {
  ScanItem({
    required this.title,
    required this.path,
    this.checkedByDefault = true,
    this.cleanable = true,
    this.risk = CleanupRisk.low,
    this.note,
    this.groupKey,
    this.appPath,
  });

  final String title;
  final String path;
  final bool checkedByDefault;

  /// false 表示只展示占用,不能由本工具直接删除。
  final bool cleanable;

  /// 用于默认勾选、确认提示和 UI 风险展示。
  final CleanupRisk risk;

  /// 清理前需要用户知晓的风险提示
  final String? note;

  /// 应用缓存分组键,bundle id 或缓存目录名
  final String? groupKey;

  /// 匹配到的 .app 路径,用于获取应用图标
  final String? appPath;

  /// -1 表示尚未扫描
  int size = -1;
  bool checked = false;
  bool cleaned = false;
}

/// 同一应用的多个缓存位置聚合
class AppCacheGroup {
  AppCacheGroup({
    required this.key,
    required this.name,
    required this.items,
    this.appPath,
  });

  final String key;
  final String name;
  final String? appPath;
  final List<ScanItem> items;

  Iterable<ScanItem> get cleanableItems => items.where((i) => i.cleanable);

  int get totalSize =>
      items.fold(0, (sum, i) => sum + (i.size > 0 ? i.size : 0));

  int get selectedSize => items.fold(
    0,
    (sum, i) => sum + (i.cleanable && i.checked && i.size > 0 ? i.size : 0),
  );

  bool get hasCleanableContent =>
      cleanableItems.any((i) => !i.cleaned && i.size > 0);

  bool get cleaned {
    final cleanable = cleanableItems.toList();
    return cleanable.isNotEmpty && cleanable.every((i) => i.cleaned);
  }

  /// 图标与"打开目录"取该组体积最大的缓存位置
  ScanItem get primaryItem => items.reduce((a, b) => b.size > a.size ? b : a);
}

List<AppCacheGroup> buildAppCacheGroups(
  List<ScanItem> items, {
  bool sortBySize = false,
}) {
  final byKey = <String, List<ScanItem>>{};
  for (final item in items) {
    byKey.putIfAbsent(item.groupKey ?? item.path, () => []).add(item);
  }
  final groups = byKey.entries.map((entry) {
    final members = List<ScanItem>.of(entry.value);
    if (sortBySize) {
      members.sort((a, b) => b.size.compareTo(a.size));
    }
    final named = members.firstWhere(
      (i) => i.appPath != null,
      orElse: () => members.first,
    );
    return AppCacheGroup(
      key: entry.key,
      name: named.title,
      appPath: named.appPath,
      items: members,
    );
  }).toList();
  if (sortBySize) {
    groups.sort((a, b) => b.totalSize.compareTo(a.totalSize));
  }
  return groups;
}

String formatBytes(int bytes) {
  if (bytes < 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}
