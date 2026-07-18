import 'dart:async';
import 'dart:typed_data';

import '../core/clock/clock.dart';
import '../core/utils/id_gen.dart';
import 'gateways.dart';

/// Debug Mock 实现。UI 必须明显标注“模拟能力”；
/// Release 构建通过 PlatformRegistry 断言禁止静默启用（见 platform_registry.dart）。

class MockOcrGateway implements OcrGateway {
  MockOcrGateway({this.sampleText});

  /// 为 demo 图片返回的固定文本（按行拆 block）。
  final String? sampleText;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<OcrResult> recognizeImage({
    required String sandboxPath,
    List<String> languageHints = const ['zh-Hans'],
    bool detectOrientation = true,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final text = sampleText ??
        '校园创新体验日\n报名截止：7月20日 18:00\n活动时间：7月25日 14:00—16:30\n'
            '地点：大学生活动中心 201\n入场码：A7281';
    final lines = text.split('\n');
    return OcrResult(
      requestId: IdGen.newId(),
      imageWidth: 1080,
      imageHeight: 2400,
      fullText: text,
      blocks: [
        for (var i = 0; i < lines.length; i++)
          OcrResultBlock(
            text: lines[i],
            confidence: 0.95,
            left: 0.08,
            top: 0.15 + i * 0.08,
            right: 0.9,
            bottom: 0.21 + i * 0.08,
            lineIndex: i,
          ),
      ],
      engine: 'mock',
      durationMs: 400,
    );
  }
}

class MockShareGateway implements ShareGateway {
  final StreamController<SharedItem> _controller =
      StreamController.broadcast();
  SharedItem? _initial;
  final Set<String> _consumed = {};

  /// 测试/演示注入。
  void emit(SharedItem item) => _controller.add(item);
  set initialShare(SharedItem? item) => _initial = item;

  @override
  Future<SharedItem?> getInitialShare() async =>
      _initial != null && !_consumed.contains(_initial!.id) ? _initial : null;

  @override
  Future<void> consumeInitialShare(String id) async => _consumed.add(id);

  @override
  Stream<SharedItem> get sharedItems => _controller.stream;

  @override
  Future<SharedItem?> pickImage() async => null; // UI 层用 demo 图代替
}

class MockReminderGateway implements ReminderGateway {
  MockReminderGateway(this._clock);

  final Clock _clock;
  final Map<int, ReminderPayload> scheduled = {};
  final StreamController<ReminderActionEvent> _actions =
      StreamController.broadcast();
  int _nextId = 1;
  bool permissionGranted = true;

  /// 测试注入通知行为。
  void emitAction(ReminderActionEvent e) => _actions.add(e);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermissionIfNeeded() async => permissionGranted;

  @override
  Future<int> scheduleCalendarReminder(ReminderPayload payload) async {
    assert(payload.triggerAt.isAfter(_clock.now()), '不得创建已过去的提醒');
    final id = _nextId++;
    scheduled[id] = payload;
    return id;
  }

  @override
  Future<void> cancelReminder(int platformId) async =>
      scheduled.remove(platformId);

  @override
  Future<List<int>> getScheduledReminderIds() async =>
      scheduled.keys.toList();

  @override
  Stream<ReminderActionEvent> get actions => _actions.stream;
}

class MockLiveViewGateway implements LiveViewGateway {
  final Map<String, DateTime> active = {};
  bool supported = true;
  bool enabled = true;
  bool entitled = true;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabledByUser() async => enabled;

  @override
  Future<bool> hasEntitlement() async => entitled;

  @override
  Future<void> startCountdown({
    required String cardId,
    required String title,
    required DateTime targetAt,
    required String scene,
  }) async =>
      active[cardId] = targetAt;

  @override
  Future<void> stop(String cardId) async => active.remove(cardId);
}

/// 生成 1x1 PNG 字节（测试与 Mock 分享用，不含个人信息）。
Uint8List tinyPngBytes() => Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
