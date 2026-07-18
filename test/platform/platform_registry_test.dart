import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/core/clock/clock.dart';
import 'package:freshcue/platform/capabilities.dart';
import 'package:freshcue/platform/mock_gateways.dart';
import 'package:freshcue/platform/platform_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clock = FixedClock(DateTime(2026, 7, 18, 10));

  test('桥接缺席（Debug 测试环境）→ 降级 Mock 并置 usingMocks', () async {
    // 注入 unbridged 快照，模拟桥接不存在。
    final reg = await PlatformRegistry.create(
      clock,
      capabilities: const PlatformCapabilities.unbridged(),
    );
    expect(reg.usingMocks, isTrue);
    expect(reg.ocr, isA<MockOcrGateway>());
    expect(reg.capabilities.bridged, isFalse);
  });

  test('桥接存在 → 使用真实 Channel 网关，不启用 Mock', () async {
    final reg = await PlatformRegistry.create(
      clock,
      capabilities: PlatformCapabilities.fromMap(const <Object?, Object?>{
        'platform': 'ohos',
        'apiVersion': 24,
        'bridgeVersion': 1,
        'kits': <Object?, Object?>{},
      }),
    );
    expect(reg.usingMocks, isFalse);
    expect(reg.ocr, isNot(isA<MockOcrGateway>()));
  });

  test('forceMock=true 在测试（非 Release）下允许', () async {
    final reg = await PlatformRegistry.create(clock, forceMock: true);
    expect(reg.usingMocks, isTrue);
  });
}
