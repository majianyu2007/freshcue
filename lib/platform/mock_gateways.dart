import 'dart:async';
import 'dart:convert';
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
  Future<OcrModelStatus> getModelStatus() async => const OcrModelStatus(
    coreVisionSupported: true,
    installed: false,
    version: 'mock',
    downloadBytes: 0,
    provider: OcrProvider.mock,
  );

  @override
  Future<OcrModelStatus> downloadModels(OcrDownloadSource source) =>
      getModelStatus();

  @override
  Future<OcrModelStatus> deleteModels() => getModelStatus();

  @override
  Future<OcrResult> recognizeImage({
    required String sandboxPath,
    List<String> languageHints = const ['zh-Hans'],
    bool detectOrientation = true,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final text =
        sampleText ??
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
      provider: OcrProvider.mock,
      durationMs: 400,
    );
  }
}

class MockShareGateway implements ShareGateway {
  final StreamController<SharedItem> _controller = StreamController.broadcast();
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

  @override
  Future<SharedItem?> capturePhoto() async => null;

  @override
  Future<void> shareText({required String title, required String text}) async {}
}

class MockReminderGateway implements ReminderGateway {
  MockReminderGateway(this._clock);

  final Clock _clock;
  final Map<int, ReminderPayload> scheduled = {};
  final StreamController<ReminderActionEvent> _actions =
      StreamController.broadcast();
  int _nextId = 1;
  bool permissionGranted = true;
  (String, String)? lastInstantNotification;
  LiveActivitySnapshot? liveActivity;

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
  Future<List<int>> getScheduledReminderIds() async => scheduled.keys.toList();

  @override
  Future<void> publishInstantNotification({
    required String title,
    required String body,
  }) async {
    lastInstantNotification = (title, body);
  }

  @override
  Future<void> syncLiveActivity(LiveActivitySnapshot? snapshot) async {
    liveActivity = snapshot;
  }

  @override
  Stream<ReminderActionEvent> get actions => _actions.stream;
}

class MockFormGateway implements FormGateway {
  List<FormCardSnapshot> cards = const [];

  @override
  Future<void> updateCards(List<FormCardSnapshot> cards) async {
    this.cards = List.unmodifiable(cards);
  }
}

/// 生成 64x64 PNG 字节（测试与 Mock 分享用，不含个人信息）。
Uint8List tinyPngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAZ0lEQVR42u3QsQ0AIAgAMOT/'
  'd42JC/wB7Qk99/2KxTKWEyBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAAB'
  'AgQIECBAgAABAgQIECBAgAABAgQIECBAgAABEzSPSQRlWU94vAAAAABJRU5ErkJggg==',
);
