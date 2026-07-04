import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:clean_mac/cleaner.dart';
import 'package:clean_mac/models.dart';

void main() {
  test('scan-only items are excluded from selected size', () {
    final category = ScanCategory(
      kind: CategoryKind.review,
      title: 'review',
      description: 'review',
      items: [
        ScanItem(
            title: 'Docker data',
            path: '/u/Library/Containers/com.docker.docker',
            cleanable: false,
          )
          ..checked = true
          ..size = 1024,
        ScanItem(title: 'Cache', path: '/u/Library/Caches/app')
          ..checked = true
          ..size = 2048,
      ],
    );

    expect(category.totalSize, 3072);
    expect(category.selectedSize, 2048);
  });

  test('cleaner denies broad containers and normalized escape paths', () async {
    final home = Platform.environment['HOME']!;
    final outcomes = await Cleaner.clean([
      '$home/Library/Containers/com.example.app/Data/Documents',
      '$home/Library/Caches/../Documents',
    ]);

    expect(outcomes, hasLength(2));
    expect(outcomes.every((o) => o.error != null), isTrue);
    expect(outcomes.every((o) => o.remainSize == 0), isTrue);
  });
}
