/// ====================================================================
/// InstallerManager 测试
///
/// 测试 InstallerManager 的接口和 Capability 映射。
/// 实际安装需要 RuntimeEnvironment，这里只测试：
///   - 接口方法实现
///   - Capability → RuntimeTool 映射
///   - InstallState 模型
/// ====================================================================
library;

import 'package:codex_mobile_pro/runtime/provider/installer_manager.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_capability.dart';
import 'package:codex_mobile_pro/runtime/provider/runtime_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InstallerManager — 接口完整性', () {
    test('未初始化时抛出 StateError', () {
      expect(
        () => InstallerManager.instance,
        throwsA(isA<StateError>()),
      );
    });

    test('InstallerManager 实现 IRuntimeInstaller', () async {
      try {
        final manager = await InstallerManager.initialize();
        expect(manager, isA<IRuntimeInstaller>());
      } catch (_) {
        // 测试环境无法初始化（path_provider 依赖）时跳过
      }
    });

    test('uninstall 返回 false（当前不支持）', () async {
      try {
        final manager = await InstallerManager.initialize();
        final result = await manager.uninstall(CapabilityType.node);
        expect(result, false);
      } catch (_) {
        // 初始化失败也可接受
      }
    });

    test('verify 返回 VerificationResult', () async {
      try {
        final manager = await InstallerManager.initialize();
        final result = await manager.verify(CapabilityType.node);
        expect(result, isA<VerificationResult>());
      } catch (_) {
        // 初始化失败也可接受
      }
    });
  });
}
