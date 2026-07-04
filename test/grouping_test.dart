import 'package:flutter_test/flutter_test.dart';

import 'package:clean_mac/models.dart';

void main() {
  test('同一应用的普通缓存与沙盒缓存合并为一组', () {
    final items = [
      ScanItem(
        title: '微信',
        path: '/u/Library/Caches/com.tencent.xinWeChat',
        groupKey: 'com.tencent.xinWeChat',
        appPath: '/Applications/WeChat.app',
      )..size = 100,
      ScanItem(
        title: 'com.tencent.xinWeChat',
        path: '/u/Library/Containers/com.tencent.xinWeChat/Data/Library/Caches',
        groupKey: 'com.tencent.xinWeChat',
      )..size = 50,
      ScanItem(
        title: 'Google',
        path: '/u/Library/Caches/Google',
        groupKey: 'Google',
      )..size = 200,
    ];

    final groups = buildAppCacheGroups(items, sortBySize: true);

    expect(groups.length, 2);
    expect(groups[0].name, 'Google');
    expect(groups[0].totalSize, 200);
    expect(groups[1].name, '微信');
    expect(groups[1].appPath, '/Applications/WeChat.app');
    expect(groups[1].totalSize, 150);
    expect(groups[1].items.length, 2);
    expect(groups[1].primaryItem.size, 100);
  });

  test('未扫描的负数大小不计入组总大小', () {
    final items = [
      ScanItem(title: 'A', path: '/u/Library/Caches/a', groupKey: 'a')
        ..size = -1,
      ScanItem(title: 'A2', path: '/u/Library/Caches/a2', groupKey: 'a')
        ..size = 30,
    ];
    final groups = buildAppCacheGroups(items);
    expect(groups.single.totalSize, 30);
  });
}
