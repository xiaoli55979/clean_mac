import 'package:flutter/services.dart';

/// 通过原生 NSWorkspace 获取任意路径的 Finder 图标 PNG
class AppIconService {
  static const _channel = MethodChannel('clean_mac/icons');
  static final _pending = <String, Future<Uint8List?>>{};
  static final _loaded = <String, Uint8List?>{};

  /// 已加载过的图标同步取,避免列表重建时闪烁
  static Uint8List? cached(String path) => _loaded[path];

  static Future<Uint8List?> iconFor(String path) =>
      _pending.putIfAbsent(path, () async {
        Uint8List? bytes;
        try {
          bytes = await _channel
              .invokeMethod<Uint8List>('appIcon', {'path': path, 'size': 64});
        } catch (_) {}
        _loaded[path] = bytes;
        return bytes;
      });
}
