import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'models.dart';

class SizeUpdate {
  const SizeUpdate(this.path, this.size);

  final String path;
  final int size;
}

class Scanner {
  /// 枚举所有可清理目标,不计算大小
  static Future<List<ScanCategory>> discoverTargets() => Isolate.run(_discover);

  static List<ScanCategory> _discover() {
    final home = Platform.environment['HOME'] ?? '';
    final appNames = _installedAppNames(home);

    void addIfExists(
      List<ScanItem> list,
      String title,
      String path, {
      bool checked = true,
      bool cleanable = true,
      CleanupRisk risk = CleanupRisk.low,
      String? note,
    }) {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        list.add(
          ScanItem(
            title: title,
            path: path,
            checkedByDefault: cleanable && checked,
            cleanable: cleanable,
            risk: cleanable ? risk : CleanupRisk.scanOnly,
            note: note,
          ),
        );
      }
    }

    final system = <ScanItem>[];
    addIfExists(
      system,
      '用户日志',
      '$home/Library/Logs',
      checked: false,
      note: '日志可帮助排查问题,建议确认后再清理',
    );
    addIfExists(
      system,
      '应用窗口恢复状态',
      '$home/Library/Saved Application State',
      checked: false,
      note: '清理后应用不再恢复上次打开的窗口',
    );
    addIfExists(
      system,
      '废纸篓',
      '$home/.Trash',
      checked: false,
      risk: CleanupRisk.high,
      note: '清空后无法恢复',
    );
    system.addAll(_downloadResidues(home));

    final developer = <ScanItem>[];
    addIfExists(
      developer,
      'Xcode 编译产物 (DerivedData)',
      '$home/Library/Developer/Xcode/DerivedData',
      risk: CleanupRisk.medium,
      note: '下次编译自动重新生成',
    );
    addIfExists(
      developer,
      'Xcode 归档 (Archives)',
      '$home/Library/Developer/Xcode/Archives',
      checked: false,
      cleanable: false,
      note: '包含已归档的 App,本工具只展示占用,不直接删除',
    );
    addIfExists(
      developer,
      'iOS 设备支持文件',
      '$home/Library/Developer/Xcode/iOS DeviceSupport',
      checked: false,
      risk: CleanupRisk.high,
      note: '连接设备时可重新生成,但会影响首次真机调试速度',
    );
    addIfExists(
      developer,
      'iOS 模拟器缓存',
      '$home/Library/Developer/CoreSimulator/Caches',
    );
    addIfExists(developer, 'CocoaPods 缓存', '$home/Library/Caches/CocoaPods');
    addIfExists(developer, 'Homebrew 缓存', '$home/Library/Caches/Homebrew');
    addIfExists(developer, 'npm 缓存', '$home/.npm/_cacache');
    addIfExists(developer, 'Yarn 缓存', '$home/Library/Caches/Yarn');
    addIfExists(developer, 'pnpm 缓存', '$home/Library/Caches/pnpm');
    addIfExists(
      developer,
      'Gradle 缓存',
      '$home/.gradle/caches',
      checked: false,
      risk: CleanupRisk.high,
      note: '下次构建需重新下载依赖,网络不稳定时不建议清',
    );
    addIfExists(developer, 'pip 缓存', '$home/Library/Caches/pip');
    addIfExists(developer, 'Go 编译缓存', '$home/Library/Caches/go-build');
    addIfExists(
      developer,
      'Dart/Pub 全局缓存',
      '$home/.pub-cache',
      checked: false,
      risk: CleanupRisk.high,
      note: '会删除全局包缓存和 git 包缓存,下次 Flutter/Dart 构建会重新下载',
    );
    addIfExists(
      developer,
      'CocoaPods 全局仓库缓存',
      '$home/.cocoapods',
      checked: false,
      risk: CleanupRisk.high,
      note: '会影响下次 pod install 速度,建议只在空间紧张时清理',
    );
    developer.addAll(_flutterProjectCaches(home));

    final claimed = developer.map((e) => e.path).toSet();

    final appCache = <ScanItem>[];
    try {
      for (final e in Directory(
        '$home/Library/Caches',
      ).listSync(followLinks: false)) {
        if (claimed.contains(e.path)) continue;
        final name = _basename(e.path);
        if (name.startsWith('.')) continue;
        final app = appNames[name];
        appCache.add(
          ScanItem(
            title: app?.name ?? name,
            path: e.path,
            groupKey: name,
            appPath: app?.path,
          ),
        );
      }
    } catch (_) {}

    // 沙盒应用的缓存;部分系统应用容器受 TCC 保护,读不到则跳过
    try {
      for (final e in Directory(
        '$home/Library/Containers',
      ).listSync(followLinks: false)) {
        final bundleId = _basename(e.path);
        final cachePath = '${e.path}/Data/Library/Caches';
        if (FileSystemEntity.typeSync(cachePath, followLinks: false) ==
            FileSystemEntityType.directory) {
          final app = appNames[bundleId];
          appCache.add(
            ScanItem(
              title: app?.name ?? bundleId,
              path: cachePath,
              groupKey: bundleId,
              appPath: app?.path,
            ),
          );
        }
      }
    } catch (_) {}

    final review = _reviewTargets(home);

    return [
      ScanCategory(
        kind: CategoryKind.appCache,
        title: '应用缓存',
        description: '各应用产生的缓存文件,清理后应用会自动重建',
        items: appCache,
      ),
      ScanCategory(
        kind: CategoryKind.system,
        title: '系统垃圾',
        description: '日志、窗口状态、未完成下载等临时文件',
        items: system,
      ),
      ScanCategory(
        kind: CategoryKind.developer,
        title: '开发者垃圾',
        description: 'Xcode、Flutter、包管理器等开发工具产生的缓存',
        items: developer,
      ),
      ScanCategory(
        kind: CategoryKind.review,
        title: '空间复核',
        description: '高风险或需专用工具处理的占用,本工具只展示不直接删除',
        items: review,
      ),
    ];
  }

  /// 并发计算各路径大小,逐个返回结果
  static Stream<SizeUpdate> computeSizes(
    List<String> paths, {
    int workers = 4,
  }) {
    final controller = StreamController<SizeUpdate>();
    final port = ReceivePort();
    final chunks = List.generate(workers, (_) => <String>[]);
    for (var i = 0; i < paths.length; i++) {
      chunks[i % workers].add(paths[i]);
    }
    var live = chunks.where((c) => c.isNotEmpty).length;
    if (live == 0) {
      port.close();
      controller.close();
      return controller.stream;
    }
    for (final chunk in chunks.where((c) => c.isNotEmpty)) {
      Isolate.spawn(_sizeWorker, [port.sendPort, chunk]);
    }
    port.listen((message) {
      if (message == null) {
        live--;
        if (live == 0) {
          port.close();
          controller.close();
        }
      } else {
        final m = message as List;
        controller.add(SizeUpdate(m[0] as String, m[1] as int));
      }
    });
    return controller.stream;
  }

  static void _sizeWorker(List args) {
    final port = args[0] as SendPort;
    final paths = args[1] as List<String>;
    for (final p in paths) {
      port.send([p, sizeOfSync(p)]);
    }
    port.send(null);
  }

  /// 计算文件或目录大小,无权限的子目录跳过
  static int sizeOfSync(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      try {
        return File(path).statSync().size;
      } catch (_) {
        return 0;
      }
    }
    if (type != FileSystemEntityType.directory) return 0;
    var total = 0;
    final stack = <String>[path];
    while (stack.isNotEmpty) {
      List<FileSystemEntity> entries;
      try {
        entries = Directory(stack.removeLast()).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        if (e is File) {
          try {
            total += e.statSync().size;
          } catch (_) {}
        } else if (e is Directory) {
          stack.add(e.path);
        }
      }
    }
    return total;
  }

  static List<ScanItem> _downloadResidues(String home) {
    final items = <ScanItem>[];
    try {
      for (final e in Directory(
        '$home/Downloads',
      ).listSync(followLinks: false)) {
        if (e is! File) continue;
        final name = _basename(e.path).toLowerCase();
        if (name.endsWith('.crdownload') || name.endsWith('.download')) {
          items.add(
            ScanItem(
              title: '未完成下载文件',
              path: e.path,
              checkedByDefault: false,
              risk: CleanupRisk.medium,
              note: '浏览器未完成下载残留,确认不再下载后可清理',
            ),
          );
        } else if (_isLargeArchiveCandidate(e.path)) {
          items.add(
            ScanItem(
              title: '下载目录大文件',
              path: e.path,
              checkedByDefault: false,
              cleanable: false,
              risk: CleanupRisk.scanOnly,
              note: '可能是安装包或交付物,本工具只展示占用',
            ),
          );
        }
      }
    } catch (_) {}
    return items;
  }

  static bool _isLargeArchiveCandidate(String path) {
    final name = _basename(path).toLowerCase();
    if (!name.endsWith('.dmg') && !name.endsWith('.zip')) return false;
    try {
      return File(path).statSync().size >= 500 * 1024 * 1024;
    } catch (_) {
      return false;
    }
  }

  static List<ScanItem> _flutterProjectCaches(String home) {
    final rootPath = '$home/Documents/Workspace/flutter';
    final root = Directory(rootPath);
    if (!root.existsSync()) return [];

    final out = <ScanItem>[];
    final stack = <_ScanDir>[_ScanDir(rootPath, 0)];
    final seen = <String>{};
    const maxDepth = 7;
    const skipped = {
      '.git',
      '.idea',
      '.gradle',
      'Pods',
      'node_modules',
      'DerivedData',
    };

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = Directory(current.path).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        if (e is! Directory) continue;
        final name = _basename(e.path);
        if (skipped.contains(name)) continue;
        if (name == 'build' || name == '.dart_tool') {
          final parent = _dirname(e.path);
          if (File('$parent/pubspec.yaml').existsSync() && seen.add(e.path)) {
            final label = _relativeLabel(parent, rootPath);
            out.add(
              ScanItem(
                title: name == 'build'
                    ? 'Flutter build 产物 ($label)'
                    : 'Flutter .dart_tool ($label)',
                path: e.path,
                checkedByDefault: false,
                risk: CleanupRisk.medium,
                note: '项目级可重建缓存,默认不选;清理后首次构建会变慢',
              ),
            );
          }
          continue;
        }
        if (current.depth < maxDepth) {
          stack.add(_ScanDir(e.path, current.depth + 1));
        }
      }
    }
    return out;
  }

  static List<ScanItem> _reviewTargets(String home) {
    final items = <ScanItem>[];

    void addReview(String title, String path, String note) {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        items.add(
          ScanItem(
            title: title,
            path: path,
            checkedByDefault: false,
            cleanable: false,
            risk: CleanupRisk.scanOnly,
            note: note,
          ),
        );
      }
    }

    addReview(
      '系统级 iOS 模拟器 Runtime',
      '/Library/Developer/CoreSimulator',
      '不要直接删除目录;请通过 Xcode Components 或 xcrun simctl runtime 管理',
    );
    addReview(
      '用户 iOS 模拟器设备数据',
      '$home/Library/Developer/CoreSimulator/Devices',
      '不要整体删除;建议只用 xcrun simctl delete unavailable 清理失效设备',
    );
    addReview(
      'Android SDK',
      '$home/Library/Android/sdk',
      'SDK/NDK 是开发环境依赖,请通过 Android Studio SDK Manager 管理',
    );
    addReview(
      'Docker Desktop 数据',
      '$home/Library/Containers/com.docker.docker',
      '可能包含镜像、容器、卷和数据库;请使用 Docker Desktop 或 docker system prune',
    );

    const appSupport = {
      'Claude': 'Claude 应用数据',
      'Cursor': 'Cursor 应用数据',
      'Kiro': 'Kiro 应用数据',
      'BitBrowser': 'BitBrowser 应用数据',
      'com.netease.mumu.nemux': '网易 MuMu 数据',
      'JetBrains': 'JetBrains 应用数据',
      'Code': 'VS Code 应用数据',
      'DingTalkMac': '钉钉应用数据',
      'Microsoft Edge': 'Microsoft Edge 应用数据',
      'bilibili': '哔哩哔哩应用数据',
      '抖音': '抖音应用数据',
      'adspower_global': 'AdsPower 应用数据',
      'Telegram Desktop': 'Telegram 应用数据',
      'Postman': 'Postman 应用数据',
    };
    for (final entry in appSupport.entries) {
      addReview(
        entry.value,
        '$home/Library/Application Support/${entry.key}',
        'Application Support 可能包含账号、数据库、离线文件或配置,本工具不直接删除',
      );
    }

    return items;
  }

  /// 扫描已安装应用,建立 bundle id 到应用名与 .app 路径的映射
  static Map<String, ({String name, String path})> _installedAppNames(
    String home,
  ) {
    final names = <String, ({String name, String path})>{};
    final roots = [
      '/Applications',
      '$home/Applications',
      '/System/Applications',
      '/System/Applications/Utilities',
    ];
    for (final root in roots) {
      List<FileSystemEntity> entries;
      try {
        entries = Directory(root).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        if (e is! Directory) continue;
        if (e.path.endsWith('.app')) {
          _readAppInfo(e.path, names);
        } else {
          try {
            for (final sub in Directory(e.path).listSync(followLinks: false)) {
              if (sub is Directory && sub.path.endsWith('.app')) {
                _readAppInfo(sub.path, names);
              }
            }
          } catch (_) {}
        }
      }
    }
    return names;
  }

  static void _readAppInfo(
    String appPath,
    Map<String, ({String name, String path})> out,
  ) {
    try {
      final result = Process.runSync('plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        '$appPath/Contents/Info.plist',
      ]);
      if (result.exitCode != 0) return;
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final bundleId = data['CFBundleIdentifier'] as String?;
      if (bundleId == null) return;
      final fallback = _basename(appPath).replaceAll('.app', '');
      final name =
          (data['CFBundleDisplayName'] ?? data['CFBundleName'] ?? fallback)
              as String;
      out[bundleId] = (name: name, path: appPath);
    } catch (_) {}
  }

  static String _relativeLabel(String path, String root) {
    if (path == root) return _basename(root);
    if (path.startsWith('$root/')) return path.substring(root.length + 1);
    return _basename(path);
  }

  static String _basename(String path) => path.split('/').last;

  static String _dirname(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }
}

class _ScanDir {
  const _ScanDir(this.path, this.depth);

  final String path;
  final int depth;
}
