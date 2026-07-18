import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/app/composition.dart';

void main() {
  group('choosePersistence（持久化后端决策，独立于 capability 握手）', () {
    test('OHOS + 有沙箱目录 → SQL', () {
      expect(
        choosePersistence(operatingSystem: 'ohos', sandboxDir: '/data/app/el2'),
        PersistenceChoice.ohosSql,
      );
    });

    test('OHOS + 沙箱目录缺失（握手失败）→ 阻塞错误，绝不静默用内存', () {
      expect(
        choosePersistence(operatingSystem: 'ohos', sandboxDir: null),
        PersistenceChoice.ohosBlockedNoSandbox,
      );
      expect(
        choosePersistence(operatingSystem: 'ohos', sandboxDir: ''),
        PersistenceChoice.ohosBlockedNoSandbox,
      );
    });

    test('非 OHOS（桌面/测试）→ 内存', () {
      for (final os in const ['macos', 'linux', 'windows', 'android', 'ios']) {
        expect(
          choosePersistence(operatingSystem: os, sandboxDir: '/whatever'),
          PersistenceChoice.devMemory,
          reason: os,
        );
      }
    });
  });

  group('shouldUseMockGateways（Release 禁 Mock）', () {
    test('Release（isDebug=false）恒不启用 Mock——即使桥接缺席', () {
      expect(shouldUseMockGateways(bridged: false, isDebug: false), isFalse);
    });

    test('Release + 显式 forceMock=true 仍不启用 Mock', () {
      expect(
        shouldUseMockGateways(bridged: false, isDebug: false, forceMock: true),
        isFalse,
      );
    });

    test('Debug + 桥接缺席 → 默认启用 Mock', () {
      expect(shouldUseMockGateways(bridged: false, isDebug: true), isTrue);
    });

    test('Debug + 桥接存在 → 不启用 Mock', () {
      expect(shouldUseMockGateways(bridged: true, isDebug: true), isFalse);
    });

    test('Debug + forceMock=false → 强制不启用（覆盖桥接缺席默认）', () {
      expect(
        shouldUseMockGateways(bridged: false, isDebug: true, forceMock: false),
        isFalse,
      );
    });
  });
}
