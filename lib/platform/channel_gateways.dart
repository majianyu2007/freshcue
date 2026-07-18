import 'dart:async';

import 'package:flutter/services.dart';

import '../core/errors/app_failure.dart';
import '../core/utils/id_gen.dart';
import 'gateways.dart';

/// 真实 OHOS 桥接实现。ArkTS 侧代码见 ohos/entry/src/main/ets/plugins/。
/// ⚠️ 未真机验证（本机无 OHOS Flutter SDK 与设备）——见 docs/known-limitations.md。

AppFailure _mapPlatformError(PlatformException e) {
  final code = switch (e.code) {
    'ocr_unavailable' => FailureCode.ocrUnavailable,
    'permission_denied' => FailureCode.notificationPermissionDenied,
    'invalid_image' => FailureCode.imageFormatUnsupported,
    'image_too_large' => FailureCode.imageTooLarge,
    'ocr_failed' => FailureCode.ocrFailed,
    'cancelled' => FailureCode.cancelled,
    'reminder_failed' => FailureCode.reminderScheduleFailed,
    'uri_expired' => FailureCode.shareUriExpired,
    _ => FailureCode.unknown,
  };
  return AppFailure(code, debugDetail: e.code);
}

class ChannelOcrGateway implements OcrGateway {
  static const _channel = MethodChannel('freshcue/ocr');

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<OcrResult> recognizeImage({
    required String sandboxPath,
    List<String> languageHints = const ['zh-Hans'],
    bool detectOrientation = true,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('recognizeImage', {
            'uri': sandboxPath,
            'languageHints': languageHints,
            'detectOrientation': detectOrientation,
          })
          .timeout(const Duration(seconds: 45));
      if (raw == null) throw const AppFailure(FailureCode.ocrFailed);
      final blocks = (raw['blocks']! as List<Object?>)
          .map((b) => OcrResultBlock.fromMap(b! as Map<Object?, Object?>))
          .toList();
      return OcrResult(
        requestId: raw['requestId'] as String? ?? IdGen.newId(),
        imageWidth: raw['imageWidth'] as int? ?? 0,
        imageHeight: raw['imageHeight'] as int? ?? 0,
        fullText: raw['fullText'] as String? ?? '',
        blocks: blocks,
        provider: OcrProvider.fromWire(raw['engine']),
        durationMs: raw['durationMs'] as int? ?? 0,
      );
    } on TimeoutException {
      throw const AppFailure(FailureCode.ocrTimeout);
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    } on MissingPluginException {
      throw const AppFailure(
        FailureCode.ocrUnavailable,
        debugDetail: 'no plugin',
      );
    }
  }
}

class ChannelShareGateway implements ShareGateway {
  static const _channel = MethodChannel('freshcue/share');
  static const _events = EventChannel('freshcue/share/events');

  @override
  Future<SharedItem?> getInitialShare() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getInitialShare',
      );
      return raw == null ? null : _fromMap(raw);
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> consumeInitialShare(String id) async {
    try {
      await _channel.invokeMethod<void>('consumeInitialShare', {'id': id});
    } on MissingPluginException {
      // 忽略：无桥接环境。
    }
  }

  @override
  Stream<SharedItem> get sharedItems => _events.receiveBroadcastStream().map(
    (raw) => _fromMap(raw as Map<Object?, Object?>),
  );

  @override
  Future<SharedItem?> pickImage() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'pickImage',
      );
      return raw == null ? null : _fromMap(raw);
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return null;
      throw _mapPlatformError(e);
    } on MissingPluginException {
      throw const AppFailure(FailureCode.unknown, debugDetail: 'no plugin');
    }
  }

  SharedItem _fromMap(Map<Object?, Object?> m) => SharedItem(
    id: m['id']! as String,
    bytes: m['bytes']! as Uint8List,
    displayName: m['displayName'] as String?,
    extraCount: m['extraCount'] as int? ?? 0,
  );
}

class ChannelReminderGateway implements ReminderGateway {
  static const _channel = MethodChannel('freshcue/reminders');
  static const _events = EventChannel('freshcue/reminders/events');

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermissionIfNeeded() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermissionIfNeeded') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<int> scheduleCalendarReminder(ReminderPayload p) async {
    try {
      final id = await _channel.invokeMethod<int>('scheduleCalendarReminder', {
        'instanceId': p.instanceId,
        'cardId': p.cardId,
        'title': p.title,
        'body': p.body,
        'triggerAtMs': p.triggerAt.millisecondsSinceEpoch,
        'sound': p.sound,
        'vibration': p.vibration,
        'hideContentOnLockScreen': p.hideContentOnLockScreen,
      });
      if (id == null) {
        throw const AppFailure(FailureCode.reminderScheduleFailed);
      }
      return id;
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    } on MissingPluginException {
      throw const AppFailure(
        FailureCode.reminderScheduleFailed,
        debugDetail: 'no plugin',
      );
    }
  }

  @override
  Future<void> cancelReminder(int platformId) async {
    try {
      await _channel.invokeMethod<void>('cancelReminder', {'id': platformId});
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    } on MissingPluginException {
      // 无桥接环境：静默（数据库侧仍会标记取消）。
    }
  }

  @override
  Future<List<int>> getScheduledReminderIds() async {
    try {
      final list = await _channel.invokeMethod<List<Object?>>(
        'getScheduledReminderIds',
      );
      return list?.cast<int>() ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Stream<ReminderActionEvent> get actions =>
      _events.receiveBroadcastStream().map((raw) {
        final m = raw as Map<Object?, Object?>;
        return ReminderActionEvent(
          action: switch (m['action']) {
            'complete' => ReminderActionType.complete,
            'snooze_10m' => ReminderActionType.snooze10m,
            'snooze_1h' => ReminderActionType.snooze1h,
            'view_source' => ReminderActionType.viewSource,
            _ => ReminderActionType.opened,
          },
          cardId: m['cardId']! as String,
          instanceId: m['instanceId'] as String? ?? '',
        );
      });
}

class ChannelFormGateway implements FormGateway {
  static const _channel = MethodChannel('freshcue/forms');

  @override
  Future<void> updateCards(List<FormCardSnapshot> cards) async {
    try {
      await _channel.invokeMethod<void>('updateCards', {
        'cards': [
          for (final card in cards)
            {'id': card.id, 'title': card.title, 'timeLabel': card.timeLabel},
        ],
      });
    } on MissingPluginException {
      // Form Kit 是 OHOS 可选呈现层；其他平台无桥接时不影响核心流程。
    } on PlatformException catch (error) {
      throw AppFailure(FailureCode.unknown, debugDetail: error.code);
    }
  }
}
