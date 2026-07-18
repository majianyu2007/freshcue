import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/platform/capabilities.dart';
import 'package:freshcue/platform/gateways.dart';

void main() {
  group('PlatformCapabilities 解析与缺字段兼容', () {
    test('完整 JSON 正确解析', () {
      final caps = PlatformCapabilities.fromMap(<Object?, Object?>{
        'platform': 'ohos',
        'apiVersion': 24,
        'bridgeVersion': 1,
        'filesDir': '/data/app/files',
        'kits': <Object?, Object?>{
          'ocr': <Object?, Object?>{
            'compiled': true,
            'available': false,
            'reason': 'device_unsupported',
            'provider': 'offline',
          },
          'reminders': <Object?, Object?>{'compiled': true, 'available': true},
        },
      });
      expect(caps.isOhos, isTrue);
      expect(caps.apiVersion, 24);
      expect(caps.filesDir, '/data/app/files');
      expect(caps.kit('ocr').compiled, isTrue);
      expect(caps.kit('ocr').available, isFalse);
      expect(caps.kit('ocr').reason, 'device_unsupported');
      expect(caps.kit('ocr').provider, OcrProvider.offline);
      expect(caps.kit('reminders').available, isTrue);
    });

    test('缺字段安全降级（不崩溃）', () {
      final caps = PlatformCapabilities.fromMap(<Object?, Object?>{
        'platform': 'ohos',
        // 缺 apiVersion / bridgeVersion / filesDir / kits
      });
      expect(caps.apiVersion, 0);
      expect(caps.bridgeVersion, 0);
      expect(caps.filesDir, isNull);
      // 未上报的 kit 返回 missing 默认值。
      final k = caps.kit('ocr');
      expect(k.compiled, isFalse);
      expect(k.available, isFalse);
      expect(k.reason, 'missing');
    });

    test('kit 值非 Map 时降级为 missing', () {
      final caps = PlatformCapabilities.fromMap(<Object?, Object?>{
        'platform': 'ohos',
        'kits': <Object?, Object?>{'ocr': 'garbage'},
      });
      expect(caps.kit('ocr').reason, 'missing');
    });

    test('unbridged 快照（桌面/测试）', () {
      const caps = PlatformCapabilities.unbridged();
      expect(caps.bridged, isFalse);
      expect(caps.isOhos, isFalse);
      expect(caps.kit('reminders').compiled, isFalse);
    });

    test('reason 机器码 → 中文', () {
      expect(
        const KitCapability(
          compiled: true,
          available: false,
          reason: 'device_unsupported',
        ).reasonLabel,
        '设备不支持',
      );
      expect(
        const KitCapability(
          compiled: false,
          available: false,
          reason: 'not_compiled',
        ).reasonLabel,
        '未编译进当前构建',
      );
      expect(
        const KitCapability(
          compiled: false,
          available: false,
          reason: 'feature_disabled',
        ).reasonLabel,
        '实验开关未启用',
      );
    });
  });

  group('OCR provider contract', () {
    test('wire values are explicit and unknown values fail closed', () {
      expect(OcrProvider.fromWire('coreVision'), OcrProvider.coreVision);
      expect(OcrProvider.fromWire('offline'), OcrProvider.offline);
      expect(OcrProvider.fromWire('mock'), OcrProvider.mock);
      expect(OcrProvider.fromWire('core_vision'), OcrProvider.none);
      expect(OcrProvider.fromWire(null), OcrProvider.none);
    });

    test('provider labels are user-facing and unambiguous', () {
      expect(OcrProvider.coreVision.label, 'Core Vision');
      expect(OcrProvider.offline.label, '离线 OCR');
      expect(OcrProvider.mock.label, '模拟 OCR');
      expect(OcrProvider.none.label, '不可用');
    });
  });

  group('OCR 结果解析', () {
    test('confidence 缺失 → null（不伪造）', () {
      final block = OcrResultBlock.fromMap(<Object?, Object?>{
        'text': '活动时间 7月25日 14:00',
        // 无 confidence
        'left': 0.1,
        'top': 0.2,
        'right': 0.9,
        'bottom': 0.25,
        'lineIndex': 1,
      });
      expect(block.confidence, isNull);
      expect(block.text, contains('活动时间'));
    });

    test('confidence 存在 → 保留', () {
      final block = OcrResultBlock.fromMap(<Object?, Object?>{
        'text': 'x',
        'confidence': 0.87,
        'left': 0.0,
        'top': 0.0,
        'right': 1.0,
        'bottom': 0.1,
        'lineIndex': 0,
      });
      expect(block.confidence, 0.87);
    });
  });
}
