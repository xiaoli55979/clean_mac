// ignore_for_file: avoid_print

import 'dart:io';

import 'package:clean_mac/cleaner.dart';
import 'package:clean_mac/models.dart';
import 'package:clean_mac/scanner.dart';

/// 冒烟验证:真实扫描 + 白名单清理链路,只删除自建的测试目录
Future<void> main() async {
  final categories = await Scanner.discoverTargets();
  for (final c in categories) {
    print('${c.title}: ${c.items.length} 项');
  }

  final sample = categories
      .expand((c) => c.items)
      .take(8)
      .map((e) => e.path)
      .toList();
  await for (final u in Scanner.computeSizes(sample)) {
    print('  ${formatBytes(u.size).padLeft(10)}  ${u.path}');
  }

  final home = Platform.environment['HOME']!;
  final testDir = Directory('$home/Library/Caches/com.test.cleanmac-smoke')
    ..createSync();
  File('${testDir.path}/junk.bin').writeAsBytesSync(List.filled(4096, 0));
  final outcome = (await Cleaner.clean([testDir.path])).first;
  print('清理测试目录: remain=${outcome.remainSize} error=${outcome.error} '
      'leftover=${testDir.listSync().length}');
  testDir.deleteSync(recursive: true);

  final denied = (await Cleaner.clean(['$home/Desktop/nonexistent-xyz'])).first;
  print('白名单外路径: error=${denied.error}');
}
