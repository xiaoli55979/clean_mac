import 'package:flutter/foundation.dart';

import 'cleaner.dart';
import 'models.dart';
import 'scanner.dart';

enum ScanPhase { idle, discovering, sizing, done, cleaning }

class CleanSummary {
  const CleanSummary(this.freed, this.failedCount);

  final int freed;
  final int failedCount;
}

class ScanController extends ChangeNotifier {
  ScanPhase phase = ScanPhase.idle;
  List<ScanCategory> categories = [];
  int scannedCount = 0;
  int totalCount = 0;

  Iterable<ScanItem> get allItems => categories.expand((c) => c.items);

  Iterable<ScanItem> get selectedItems => allItems.where(
    (i) => i.cleanable && i.checked && !i.cleaned && i.size > 0,
  );

  bool get busy =>
      phase == ScanPhase.discovering ||
      phase == ScanPhase.sizing ||
      phase == ScanPhase.cleaning;

  int get totalSize => categories.fold(0, (s, c) => s + c.totalSize);

  int get selectedSize => categories.fold(0, (s, c) => s + c.selectedSize);

  int get selectedCount => selectedItems.length;

  Future<void> scan() async {
    if (busy) return;
    phase = ScanPhase.discovering;
    categories = [];
    scannedCount = 0;
    totalCount = 0;
    notifyListeners();

    categories = await Scanner.discoverTargets();
    final byPath = <String, ScanItem>{};
    for (final item in allItems) {
      item.checked = item.cleanable && item.checkedByDefault;
      byPath[item.path] = item;
    }
    totalCount = byPath.length;
    phase = ScanPhase.sizing;
    notifyListeners();

    await for (final update in Scanner.computeSizes(byPath.keys.toList())) {
      byPath[update.path]?.size = update.size;
      scannedCount++;
      notifyListeners();
    }

    for (final c in categories) {
      c.items.sort((a, b) => b.size.compareTo(a.size));
    }
    phase = ScanPhase.done;
    notifyListeners();
  }

  /// 应用缓存按应用聚合;扫描完成后按大小排序
  List<AppCacheGroup> appCacheGroupsFor(ScanCategory category) =>
      buildAppCacheGroups(category.items, sortBySize: phase == ScanPhase.done);

  Future<CleanSummary> cleanSelected() => _clean(selectedItems.toList());

  Future<CleanSummary> cleanGroup(AppCacheGroup group) => _clean(
    group.cleanableItems.where((i) => !i.cleaned && i.size > 0).toList(),
  );

  Future<CleanSummary> _clean(List<ScanItem> targets) async {
    if (targets.isEmpty || busy) return const CleanSummary(0, 0);
    phase = ScanPhase.cleaning;
    notifyListeners();

    final outcomes = await Cleaner.clean(targets.map((e) => e.path).toList());
    final byPath = {for (final i in allItems) i.path: i};
    var freed = 0;
    var failed = 0;
    for (final o in outcomes) {
      final item = byPath[o.path];
      if (item == null) continue;
      if (item.size > 0 && o.remainSize < item.size) {
        freed += item.size - o.remainSize;
      }
      item.size = o.remainSize;
      if (o.error != null) {
        failed++;
      } else if (o.remainSize == 0) {
        item.cleaned = true;
        item.checked = false;
      }
    }
    phase = ScanPhase.done;
    notifyListeners();
    return CleanSummary(freed, failed);
  }
}
