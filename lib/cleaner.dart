import 'dart:io';
import 'dart:isolate';

import 'scanner.dart';

class CleanOutcome {
  const CleanOutcome(this.path, this.remainSize, this.error);

  final String path;
  final int remainSize;
  final String? error;
}

class Cleaner {
  static Future<List<CleanOutcome>> clean(List<String> paths) =>
      Isolate.run(() => paths.map(_cleanOne).toList());

  /// 目录只清空内容保留目录本身,单个文件直接删除
  static CleanOutcome _cleanOne(String path) {
    final target = _normalizePath(path);
    if (!_isAllowed(target)) {
      return CleanOutcome(path, 0, '路径不在安全清理范围内,已跳过');
    }
    String? error;
    try {
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        for (final e in Directory(target).listSync(followLinks: false)) {
          try {
            e.deleteSync(recursive: true);
          } catch (err) {
            error = '$err';
          }
        }
      } else if (type == FileSystemEntityType.file) {
        File(target).deleteSync();
      } else if (type == FileSystemEntityType.link) {
        Link(target).deleteSync();
      }
    } catch (err) {
      error = '$err';
    }
    return CleanOutcome(path, Scanner.sizeOfSync(target), error);
  }

  /// 只允许删除精确安全子路径,防止误删用户数据或系统运行时。
  static bool _isAllowed(String path) {
    final homeEnv = Platform.environment['HOME'] ?? '';
    if (homeEnv.isEmpty || !path.startsWith('/')) return false;

    final home = _normalizePath(homeEnv);
    final exactContentRoots = [
      '$home/Library/Logs',
      '$home/Library/Saved Application State',
      '$home/Library/Developer/Xcode/DerivedData',
      '$home/Library/Developer/Xcode/iOS DeviceSupport',
      '$home/Library/Developer/CoreSimulator/Caches',
      '$home/.Trash',
      '$home/.npm/_cacache',
      '$home/.gradle/caches',
      '$home/.pub-cache',
      '$home/.cocoapods',
    ];
    if (exactContentRoots.any((root) => _isSameOrChild(path, root))) {
      return true;
    }

    // 普通应用缓存允许清理子项,但禁止把整个 ~/Library/Caches 作为目标。
    if (_isChildOf(path, '$home/Library/Caches')) return true;

    // 沙盒应用只能清理 Data/Library/Caches,不能触碰 Documents、Application Support 等真实数据。
    if (_isContainerCachePath(path, '$home/Library/Containers')) return true;

    // Flutter 项目缓存必须是带 pubspec.yaml 的项目根下 build 或 .dart_tool。
    if (_isFlutterProjectCache(path, '$home/Documents/Workspace/flutter')) {
      return true;
    }

    // 下载残留只允许顶层未完成下载文件。
    if (_isDownloadResidue(path, '$home/Downloads')) return true;

    return false;
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return path;
    final absolute = path.startsWith('/')
        ? path
        : '${Directory.current.path}/$path';
    try {
      final type = FileSystemEntity.typeSync(absolute, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        return Directory(absolute).resolveSymbolicLinksSync();
      }
      if (type == FileSystemEntityType.file) {
        return File(absolute).resolveSymbolicLinksSync();
      }
      if (type == FileSystemEntityType.link) {
        return Link(absolute).resolveSymbolicLinksSync();
      }
    } catch (_) {}

    final parts = <String>[];
    for (final part in absolute.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return '/${parts.join('/')}';
  }

  static bool _isSameOrChild(String path, String root) =>
      path == root || path.startsWith('$root/');

  static bool _isChildOf(String path, String root) =>
      path != root && path.startsWith('$root/');

  static bool _isContainerCachePath(String path, String containersRoot) {
    if (!path.startsWith('$containersRoot/')) return false;
    final suffix = path.substring(containersRoot.length + 1);
    final parts = suffix.split('/');
    return parts.length >= 4 &&
        parts[1] == 'Data' &&
        parts[2] == 'Library' &&
        parts[3] == 'Caches';
  }

  static bool _isFlutterProjectCache(String path, String workspaceRoot) {
    if (!path.startsWith('$workspaceRoot/')) return false;
    final name = _basename(path);
    if (name != 'build' && name != '.dart_tool') return false;
    return File('${_dirname(path)}/pubspec.yaml').existsSync();
  }

  static bool _isDownloadResidue(String path, String downloadsRoot) {
    if (_dirname(path) != downloadsRoot) return false;
    final name = _basename(path).toLowerCase();
    return name.endsWith('.crdownload') || name.endsWith('.download');
  }

  static String _basename(String path) => path.split('/').last;

  static String _dirname(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }
}
