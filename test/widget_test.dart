import 'package:flutter_test/flutter_test.dart';

import 'package:clean_mac/main.dart';
import 'package:clean_mac/models.dart';

void main() {
  testWidgets('首页展示扫描入口', (tester) async {
    await tester.pumpWidget(const CleanMacApp());
    expect(find.text('CleanMac'), findsOneWidget);
    expect(find.text('开始扫描'), findsWidgets);
  });

  test('字节格式化', () {
    expect(formatBytes(-1), '—');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });
}
