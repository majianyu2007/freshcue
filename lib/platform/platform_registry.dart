import 'package:flutter/foundation.dart';

import '../app/composition.dart';
import '../core/clock/clock.dart';
import 'capabilities.dart';
import 'channel_gateways.dart';
import 'gateways.dart';
import 'mock_gateways.dart';

/// 平台能力注册表。
/// OHOS 桥接存在（capability handshake 成功）→ 一律使用真实 Channel 网关，
/// 单项能力缺席走各自降级路径。
/// 桥接缺席：Debug 降级 Mock 并置 [usingMocks]=true（UI 显示“模拟能力”横幅）；
/// Release 绝不静默启用 Mock。
class PlatformRegistry {
  PlatformRegistry._({
    required this.ocr,
    required this.share,
    required this.reminders,
    required this.calendar,
    required this.forms,
    required this.usingMocks,
    required this.capabilities,
  });

  final OcrGateway ocr;
  final ShareGateway share;
  final ReminderGateway reminders;
  final CalendarGateway calendar;
  final FormGateway forms;
  final bool usingMocks;
  final PlatformCapabilities capabilities;

  /// [forceMock] 仅供测试注入。
  static Future<PlatformRegistry> create(
    Clock clock, {
    bool? forceMock,
    PlatformCapabilities? capabilities,
  }) async {
    final caps = capabilities ?? await CapabilityService().fetch();
    final useMock = shouldUseMockGateways(
      bridged: caps.bridged,
      isDebug: kDebugMode,
      forceMock: forceMock,
    );
    assert(() {
      if (forceMock == true && kReleaseMode) {
        throw StateError('Release 构建禁止启用 Mock 平台能力');
      }
      return true;
    }());
    if (useMock && !kReleaseMode) {
      return PlatformRegistry._(
        ocr: MockOcrGateway(),
        share: MockShareGateway(),
        reminders: MockReminderGateway(clock),
        calendar: MockCalendarGateway(),
        forms: MockFormGateway(),
        usingMocks: true,
        capabilities: caps,
      );
    }
    return PlatformRegistry._(
      ocr: ChannelOcrGateway(),
      share: ChannelShareGateway(),
      reminders: ChannelReminderGateway(),
      calendar: ChannelCalendarGateway(),
      forms: ChannelFormGateway(),
      usingMocks: false,
      capabilities: caps,
    );
  }
}
