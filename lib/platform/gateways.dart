import 'dart:typed_data';

/// OCR 结果（channel: freshcue/ocr）。
class OcrResultBlock {
  const OcrResultBlock({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.lineIndex,
  });

  factory OcrResultBlock.fromMap(Map<Object?, Object?> m) => OcrResultBlock(
    text: m['text']! as String,
    confidence: (m['confidence']! as num).toDouble(),
    left: (m['left']! as num).toDouble(),
    top: (m['top']! as num).toDouble(),
    right: (m['right']! as num).toDouble(),
    bottom: (m['bottom']! as num).toDouble(),
    lineIndex: m['lineIndex']! as int,
  );

  final String text;
  final double confidence;
  final double left, top, right, bottom;
  final int lineIndex;
}

class OcrResult {
  const OcrResult({
    required this.requestId,
    required this.imageWidth,
    required this.imageHeight,
    required this.fullText,
    required this.blocks,
    required this.engine,
    required this.durationMs,
  });

  final String requestId;
  final int imageWidth;
  final int imageHeight;
  final String fullText;
  final List<OcrResultBlock> blocks;

  /// core_vision / mock。
  final String engine;
  final int durationMs;
}

/// OCR 能力抽象。真实实现桥接 HarmonyOS Core Vision（ArkTS），
/// Mock 实现仅 Debug 可用且 UI 明显标注。
abstract interface class OcrGateway {
  Future<bool> isAvailable();
  Future<OcrResult> recognizeImage({
    required String sandboxPath,
    List<String> languageHints = const ['zh-Hans'],
    bool detectOrientation = true,
  });
}

/// 分享接收的条目。
class SharedItem {
  const SharedItem({
    required this.id,
    required this.bytes,
    this.displayName,
    this.extraCount = 0,
  });

  final String id;

  /// 桥接层已把 URI 内容读为字节，Flutter 侧不持有外部 URI 授权。
  final Uint8List bytes;
  final String? displayName;

  /// 多图分享时未导入的剩余张数（第一版只处理第一张）。
  final int extraCount;
}

/// 分享接收 + 图库选择（channel: freshcue/share）。
abstract interface class ShareGateway {
  /// 冷启动分享：应用启动时查询待处理条目。
  Future<SharedItem?> getInitialShare();

  /// 消费冷启动条目（去重，保证只处理一次）。
  Future<void> consumeInitialShare(String id);

  /// 热启动分享事件流。
  Stream<SharedItem> get sharedItems;

  /// 系统图库选择器。
  Future<SharedItem?> pickImage();
}

/// 代理提醒调度载荷。
class ReminderPayload {
  const ReminderPayload({
    required this.instanceId,
    required this.cardId,
    required this.title,
    required this.body,
    required this.triggerAt,
    this.sound = true,
    this.vibration = true,
    this.hideContentOnLockScreen = false,
  });

  final String instanceId;
  final String cardId;
  final String title;

  /// 敏感内容必须在调用前遮罩。
  final String body;
  final DateTime triggerAt;
  final bool sound;
  final bool vibration;
  final bool hideContentOnLockScreen;
}

/// 通知行为事件。
enum ReminderActionType { complete, snooze10m, snooze1h, viewSource, opened }

class ReminderActionEvent {
  const ReminderActionEvent({
    required this.action,
    required this.cardId,
    required this.instanceId,
  });

  final ReminderActionType action;
  final String cardId;
  final String instanceId;
}

/// 代理提醒能力（channel: freshcue/reminders）。
/// 真实实现桥接 @ohos.reminderAgentManager。
abstract interface class ReminderGateway {
  Future<bool> isAvailable();
  Future<bool> requestPermissionIfNeeded();

  /// 返回平台 reminder ID；失败抛 AppFailure。
  Future<int> scheduleCalendarReminder(ReminderPayload payload);
  Future<void> cancelReminder(int platformId);
  Future<List<int>> getScheduledReminderIds();

  /// 通知点击/行为事件（含冷启动补发，桥接层保证只发一次）。
  Stream<ReminderActionEvent> get actions;
}

/// 实况窗能力（channel: freshcue/live_view）。默认 feature flag 关闭。
abstract interface class LiveViewGateway {
  Future<bool> isSupported();
  Future<bool> isEnabledByUser();
  Future<bool> hasEntitlement();
  Future<void> startCountdown({
    required String cardId,
    required String title,
    required DateTime targetAt,
    required String scene,
  });
  Future<void> stop(String cardId);
}
