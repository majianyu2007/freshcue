import 'dart:typed_data';

/// OCR 结果（channel: freshcue/ocr）。
class OcrResultBlock {
  const OcrResultBlock({
    required this.text,
    this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.lineIndex,
  });

  factory OcrResultBlock.fromMap(Map<Object?, Object?> m) => OcrResultBlock(
    text: m['text']! as String,
    // Core Vision 不提供逐行置信度 → null，不得伪造。
    confidence: m['confidence'] == null
        ? null
        : (m['confidence']! as num).toDouble(),
    left: (m['left']! as num).toDouble(),
    top: (m['top']! as num).toDouble(),
    right: (m['right']! as num).toDouble(),
    bottom: (m['bottom']! as num).toDouble(),
    lineIndex: m['lineIndex']! as int,
  );

  final String text;

  /// OCR 引擎逐行置信度；引擎不提供时为 null。
  /// 与解析器的启发式 UI 分数（roleConfidence/dateConfidence）是不同概念。
  final double? confidence;
  final double left, top, right, bottom;
  final int lineIndex;
}

enum OcrProvider {
  coreVision,
  offline,
  mock,
  none;

  static OcrProvider fromWire(Object? value) => switch (value) {
    'coreVision' => OcrProvider.coreVision,
    'offline' => OcrProvider.offline,
    'mock' => OcrProvider.mock,
    _ => OcrProvider.none,
  };

  String get label => switch (this) {
    OcrProvider.coreVision => 'Core Vision',
    OcrProvider.offline => '离线 OCR',
    OcrProvider.mock => '模拟 OCR',
    OcrProvider.none => '不可用',
  };
}

class OcrResult {
  const OcrResult({
    required this.requestId,
    required this.imageWidth,
    required this.imageHeight,
    required this.fullText,
    required this.blocks,
    required this.provider,
    required this.durationMs,
  });

  final String requestId;
  final int imageWidth;
  final int imageHeight;
  final String fullText;
  final List<OcrResultBlock> blocks;

  /// 实际完成本次识别的提供方。
  final OcrProvider provider;
  final int durationMs;
}

enum OcrDownloadSource { github, ghproxy, fastly }

class OcrModelStatus {
  const OcrModelStatus({
    required this.coreVisionSupported,
    required this.installed,
    required this.version,
    required this.downloadBytes,
    required this.provider,
    this.downloadedBytes = 0,
    this.downloading = false,
  });

  const OcrModelStatus.unavailable()
    : coreVisionSupported = false,
      installed = false,
      version = 'ocr-v1',
      downloadBytes = 0,
      downloadedBytes = 0,
      downloading = false,
      provider = OcrProvider.none;

  final bool coreVisionSupported;
  final bool installed;
  final String version;
  final int downloadBytes;
  final int downloadedBytes;
  final bool downloading;

  double get downloadProgress =>
      downloadBytes == 0 ? 0 : (downloadedBytes / downloadBytes).clamp(0, 1);
  final OcrProvider provider;

  bool get ready => coreVisionSupported || installed;
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
  Future<OcrModelStatus> getModelStatus();
  Future<OcrModelStatus> downloadModels(OcrDownloadSource source);
  Future<OcrModelStatus> deleteModels();
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
  Future<SharedItem?> capturePhoto();
  Future<SharedItem?> pickImage();

  Future<void> shareText({required String title, required String text});
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

class LiveActivitySnapshot {
  const LiveActivitySnapshot({
    required this.cardId,
    required this.title,
    required this.timeLabel,
    required this.endsAt,
  });

  final String cardId;
  final String title;
  final String timeLabel;
  final DateTime endsAt;
}

/// 代理提醒能力（channel: freshcue/reminders）。
/// 真实实现桥接 @ohos.reminderAgentManager。
abstract interface class ReminderGateway {
  Future<bool> isAvailable();
  Future<bool> getNotificationPermissionStatus();
  Future<bool> requestPermissionIfNeeded();
  Future<void> openNotificationSettings();

  /// 返回平台 reminder ID；失败抛 AppFailure。
  Future<int> scheduleCalendarReminder(ReminderPayload payload);
  Future<void> cancelReminder(int platformId);
  Future<List<int>> getScheduledReminderIds();

  /// 立即发布一条本地 Notification Kit 通知。
  Future<void> publishInstantNotification({
    required String title,
    required String body,
  });

  /// 同步状态栏胶囊/锁屏实况窗；null 表示结束当前实况窗。
  Future<void> syncLiveActivity(LiveActivitySnapshot? snapshot);

  /// 通知点击/行为事件（含冷启动补发，桥接层保证只发一次）。
  Stream<ReminderActionEvent> get actions;
}

/// 系统日程载荷（channel: freshcue/calendar）。
class CalendarEventPayload {
  const CalendarEventPayload({
    required this.cardId,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.description,
    this.location,
    this.reminderMinutes = const [],
  });

  final String cardId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final String? description;
  final String? location;
  final List<int> reminderMinutes;
}

/// Calendar Kit 网关。只在用户选择“系统日程”时请求日历权限。
abstract interface class CalendarGateway {
  Future<bool> isAvailable();
  Future<bool> requestPermissionIfNeeded();
  Future<int> createEvent(CalendarEventPayload payload);
  Future<void> updateEvent(int eventId, CalendarEventPayload payload);
  Future<void> deleteEvent(int eventId);
}

/// 服务卡片仅接收展示所需的快照，不访问 Flutter 数据库。
class FormCardSnapshot {
  const FormCardSnapshot({
    required this.id,
    required this.title,
    required this.timeLabel,
  });

  final String id;
  final String title;
  final String timeLabel;
}

/// Form Kit 服务卡片数据同步（channel: freshcue/forms）。
abstract interface class FormGateway {
  Future<void> updateCards(List<FormCardSnapshot> cards);
}
