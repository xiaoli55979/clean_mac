# CleanMac

macOS 垃圾文件与应用缓存清理工具。扫描结果按应用缓存、系统垃圾、开发者垃圾和空间复核分组展示；默认只勾选低风险、可重建的缓存，高代价或需要人工判断的内容只展示占用或要求手动确认。

## 开发验证

```bash
flutter analyze
flutter test
```

## macOS 打包

```bash
./scripts/package_macos.sh
```

脚本会执行依赖解析、静态分析、测试、Release 构建、签名校验和 zip 校验。产物输出到 `dist/CleanMac-macos-release.zip`。
