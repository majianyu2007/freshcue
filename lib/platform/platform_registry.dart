import 'package:flutter/foundation.dart';

import 'channel_gateways.dart';
import 'gateways.dart';
import 'mock_gateways.dart';
import '../core/clock/clock.dart';

/// 平台能力注册表。
/// Debug：桥接缺席时自动降级 Mock，并置 [usingMocks]=true（UI 显示“模拟能力”横幅）。
/// Release：绝不静默启用 Mock —— 桥接缺席时能力不可用并走降级路径。
class PlatformRegistry {
  PlatformRegistry._({
    required this.ocr,
    required this.share,
    required this.reminders,
    required this.liveView,
    required this.usingMocks,
  });

  final OcrGateway ocr;
  final ShareGateway share;
  final ReminderGateway reminders;
  final LiveViewGateway liveView;
  final bool usingMocks;

  /// [forceMock] 仅供测试注入。
  static Future<PlatformRegistry> create(
    Clock clock, {
    bool? forceMock,
  }) async {
    final channelOcr = ChannelOcrGateway();
    final bridged = await channelOcr.isAvailable();
    final useMock = forceMock ?? (!bridged && kDebugMode);
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
        liveView: MockLiveViewGateway(),
        usingMocks: true,
      );
    }
    return PlatformRegistry._(
      ocr: channelOcr,
      share: ChannelShareGateway(),
      reminders: ChannelReminderGateway(),
      liveView: ChannelLiveViewGateway(),
      usingMocks: false,
    );
  }
}
