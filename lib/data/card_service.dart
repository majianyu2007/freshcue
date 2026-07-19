import '../core/clock/clock.dart';
import '../core/errors/app_failure.dart';
import '../core/logging/app_log.dart';
import '../core/utils/id_gen.dart';
import '../core/utils/redactor.dart';
import '../domain/entities/reminder.dart';
import '../domain/entities/temporal_card.dart';
import '../domain/enums/enums.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/reminder_policy.dart';
import '../platform/gateways.dart';
import 'database/image_asset_service.dart';

/// 应用服务：卡片全生命周期编排。
/// 数据库是提醒意图的事实来源，应用提醒与系统日程是互斥执行层。
class DeliveryResult {
  const DeliveryResult({
    required this.mode,
    this.failures = 0,
    this.permissionDenied = false,
  });

  final DeliveryMode mode;
  final int failures;
  final bool permissionDenied;
  bool get succeeded => failures == 0 && !permissionDenied;
}

class CardService {
  CardService({
    required this.cards,
    required this.assets,
    required this.ocrBlocks,
    required this.reminders,
    required this.reminderGateway,
    required this.calendarGateway,
    required this.assetService,
    required this.clock,
    this.policy = const ReminderPolicy(),
    this.showSensitiveCodes = true,
  });

  final CardRepository cards;
  final AssetRepository assets;
  final OcrBlockRepository ocrBlocks;
  final ReminderRepository reminders;
  final ReminderGateway reminderGateway;
  final CalendarGateway calendarGateway;
  final ImageAssetService assetService;
  final Clock clock;
  ReminderPolicy policy;
  bool showSensitiveCodes;

  /// 确认草稿：保存卡片与计划，再按用户选择只创建一种提醒。
  /// 返回可恢复的执行结果，UI 不会把权限拒绝或部分失败假装成成功。
  Future<DeliveryResult> confirmCard(
    TemporalCard card,
    List<ReminderPlan> plans, {
    List<ReminderInstance>? precomputedInstances,
  }) async {
    final now = clock.now();
    final confirmed = card.copyWith(
      status: CardStatus.active,
      confirmedAt: now,
      updatedAt: now,
    );
    try {
      await cards.save(confirmed);
      await reminders.savePlans(card.id, plans);
    } catch (e) {
      throw AppFailure(
        FailureCode.databaseWriteFailed,
        debugDetail: e.runtimeType.toString(),
      );
    }
    final instances =
        precomputedInstances ??
        policy.expand(confirmed, plans, now, IdGen.newId).instances;
    if (confirmed.deliveryMode == DeliveryMode.systemCalendar) {
      await reminders.replaceInstances(confirmed.id, const []);
      return _syncCalendar(confirmed, plans);
    }
    final failures = await _scheduleAll(confirmed, instances);
    return DeliveryResult(mode: DeliveryMode.appReminder, failures: failures);
  }

  /// 编辑关键时间后：取消旧提醒 → 重新展开 → 原子化重建。
  Future<DeliveryResult> rebuildDelivery(TemporalCard card) async {
    final now = clock.now();
    await _cancelAllPlatform(card.id);
    final plans = await reminders.plansByCard(card.id);
    if (card.deliveryMode == DeliveryMode.systemCalendar) {
      await reminders.replaceInstances(card.id, const []);
      await cards.save(card.copyWith(updatedAt: now));
      return _syncCalendar(card, plans);
    }
    final instances = policy.expand(card, plans, now, IdGen.newId).instances;
    await cards.save(card.copyWith(updatedAt: now));
    final failures = await _scheduleAll(card, instances);
    return DeliveryResult(mode: DeliveryMode.appReminder, failures: failures);
  }

  Future<DeliveryResult> _syncCalendar(
    TemporalCard card,
    List<ReminderPlan> plans,
  ) async {
    if (!await calendarGateway.isAvailable()) {
      return const DeliveryResult(
        mode: DeliveryMode.systemCalendar,
        failures: 1,
      );
    }
    if (!await calendarGateway.requestPermissionIfNeeded()) {
      return const DeliveryResult(
        mode: DeliveryMode.systemCalendar,
        permissionDenied: true,
      );
    }
    final payload = _calendarPayload(card, plans);
    if (payload == null) {
      return const DeliveryResult(
        mode: DeliveryMode.systemCalendar,
        failures: 1,
      );
    }
    try {
      final existingId = card.calendarEventId;
      if (existingId == null) {
        final eventId = await calendarGateway.createEvent(payload);
        try {
          await cards.save(
            card.copyWith(calendarEventId: eventId, updatedAt: clock.now()),
          );
        } on Object {
          await calendarGateway.deleteEvent(eventId);
          rethrow;
        }
      } else {
        await calendarGateway.updateEvent(existingId, payload);
      }
      return const DeliveryResult(mode: DeliveryMode.systemCalendar);
    } on AppFailure catch (failure) {
      AppLog.w('calendar', '写入日程失败: ${failure.code.name}');
      return DeliveryResult(
        mode: DeliveryMode.systemCalendar,
        failures: 1,
        permissionDenied: failure.code == FailureCode.calendarPermissionDenied,
      );
    }
  }

  CalendarEventPayload? _calendarPayload(
    TemporalCard card,
    List<ReminderPlan> plans,
  ) {
    final anchor = card.eventStartAt != null
        ? (TemporalRole.eventStart, card.eventStartAt!)
        : card.deadlineAt != null
        ? (TemporalRole.deadline, card.deadlineAt!)
        : card.expiresAt != null
        ? (TemporalRole.expiry, card.expiresAt!)
        : null;
    if (anchor == null) return null;
    final start = anchor.$2;
    final end = card.eventEndAt != null && card.eventEndAt!.isAfter(start)
        ? card.eventEndAt!
        : start.add(const Duration(minutes: 30));
    final otherTimes = card.keyTimes
        .where((item) => item.$1 != anchor.$1 || item.$2 != anchor.$2)
        .map((item) => '${item.$1.label}：${_dateText(item.$2)}');
    final details = <String>[
      ...otherTimes,
      if (card.secretValue != null)
        '码：${showSensitiveCodes ? card.secretValue : Redactor.maskSecret(card.secretValue!)}',
      if (card.notes != null && card.notes!.trim().isNotEmpty)
        card.notes!.trim(),
      '来自截期',
    ];
    final reminderMinutes =
        plans
            .where(
              (plan) =>
                  plan.enabled &&
                  plan.anchorRole == anchor.$1 &&
                  plan.offsetMinutes > 0,
            )
            .map((plan) => plan.offsetMinutes)
            .toSet()
            .toList()
          ..sort();
    return CalendarEventPayload(
      cardId: card.id,
      title: card.isSensitive && !showSensitiveCodes ? '截期日程' : card.title,
      startAt: start,
      endAt: end,
      description: details.join('\n'),
      location: card.location,
      reminderMinutes: reminderMinutes,
    );
  }

  String _dateText(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Future<int> _scheduleAll(
    TemporalCard card,
    List<ReminderInstance> instances,
  ) async {
    try {
      // 先持久化调度意图。进程若在平台调用中途退出，reconcile 可补建，
      // 不会留下数据库完全不知道的系统提醒。
      await reminders.replaceInstances(card.id, instances);
    } catch (e) {
      throw AppFailure(
        FailureCode.databaseWriteFailed,
        debugDetail: e.runtimeType.toString(),
      );
    }

    var failures = 0;
    final available = instances.isEmpty || await reminderGateway.isAvailable();
    for (final instance in instances) {
      ReminderInstance saved;
      int? platformId;
      try {
        if (!available) {
          throw const AppFailure(
            FailureCode.reminderScheduleFailed,
            debugDetail: 'gateway unavailable',
          );
        }
        platformId = await reminderGateway.scheduleCalendarReminder(
          _payloadFor(card, instance),
        );
        saved = instance.copyWith(platformReminderId: platformId);
      } on AppFailure catch (failure) {
        failures++;
        AppLog.w('reminder', '调度失败: ${failure.code.name}');
        saved = instance.copyWith(
          status: ReminderStatus.failed,
          failureReason: failure.code.name,
        );
      }
      try {
        await reminders.saveInstance(saved);
      } catch (e) {
        if (platformId != null) {
          try {
            await reminderGateway.cancelReminder(platformId);
          } on AppFailure catch (failure) {
            AppLog.w('reminder', '回滚提醒失败: ${failure.code.name}');
          }
        }
        throw AppFailure(
          FailureCode.databaseWriteFailed,
          debugDetail: e.runtimeType.toString(),
        );
      }
    }
    return failures;
  }

  ReminderPayload _payloadFor(TemporalCard card, ReminderInstance inst) {
    final next = card.nextKeyTime(inst.triggerAt);
    final semantic = next == null ? '' : '（${next.$1.label}）';
    final details = <String>[
      if (card.secretValue != null)
        '码 ${showSensitiveCodes ? card.secretValue : Redactor.maskSecret(card.secretValue!)}',
      if (card.location != null) '@${card.location}',
    ];
    final body =
        '${card.title}$semantic'
        '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
    return ReminderPayload(
      instanceId: inst.id,
      cardId: card.id,
      title: card.isSensitive && !showSensitiveCodes ? '截期提醒' : card.title,
      body: body,
      triggerAt: inst.triggerAt,
      hideContentOnLockScreen: card.isSensitive && !showSensitiveCodes,
    );
  }

  Future<void> _cancelAllPlatform(String cardId) async {
    for (final inst in await reminders.instancesByCard(cardId)) {
      final pid = inst.platformReminderId;
      if (pid != null && inst.status == ReminderStatus.scheduled) {
        try {
          await reminderGateway.cancelReminder(pid);
        } on AppFailure catch (f) {
          AppLog.w('reminder', '取消失败: ${f.code.name}');
        }
      }
    }
  }

  Future<void> complete(String cardId) =>
      _setStatus(cardId, CardStatus.completed);

  Future<void> archive(String cardId) =>
      _setStatus(cardId, CardStatus.archived);

  /// 恢复为 active（过期箱），调用方随后应引导用户重设时间。
  Future<void> restore(String cardId) => _setStatus(cardId, CardStatus.active);

  Future<void> _setStatus(String cardId, CardStatus status) async {
    final card = await cards.findById(cardId);
    if (card == null) throw const AppFailure(FailureCode.cardNotFound);
    if (status != CardStatus.active) {
      await _cancelAllPlatform(cardId);
      await _deleteCalendarEvent(card);
    }
    await cards.save(
      card.copyWith(
        status: status,
        updatedAt: clock.now(),
        calendarEventId: status == CardStatus.active
            ? card.calendarEventId
            : null,
      ),
    );
  }

  /// 删除：先取消系统提醒 → 删数据库关联 → 删沙箱图片。
  Future<void> deleteCard(String cardId) async {
    final card = await cards.findById(cardId);
    if (card == null) return;
    await _cancelAllPlatform(cardId);
    await _deleteCalendarEvent(card);
    await reminders.deleteByCard(cardId);
    await ocrBlocks.deleteByCard(cardId);
    final assetId = card.sourceAssetId;
    await cards.delete(cardId);
    if (assetId != null) {
      final asset = await assets.findById(assetId);
      if (asset != null) {
        await assets.delete(assetId);
        assetService.deleteFiles(asset); // 只删沙箱副本，不碰图库
      }
    }
  }

  Future<void> _deleteCalendarEvent(TemporalCard card) async {
    final eventId = card.calendarEventId;
    if (eventId == null) return;
    try {
      await calendarGateway.deleteEvent(eventId);
    } on AppFailure catch (failure) {
      AppLog.w('calendar', '删除日程失败: ${failure.code.name}');
    }
  }

  /// 通知行为处理（同一行为只执行一次由桥接层保证）。
  Future<void> handleAction(ReminderActionEvent e) async {
    switch (e.action) {
      case ReminderActionType.complete:
        await complete(e.cardId);
      case ReminderActionType.snooze10m:
        await _snooze(e, const Duration(minutes: 10));
      case ReminderActionType.snooze1h:
        await _snooze(e, const Duration(hours: 1));
      case ReminderActionType.viewSource:
      case ReminderActionType.opened:
      case ReminderActionType.route:
        break; // 路由层负责跳转
    }
  }

  Future<void> _snooze(ReminderActionEvent e, Duration delay) async {
    final card = await cards.findById(e.cardId);
    if (card == null) return;
    final all = await reminders.instancesByCard(e.cardId);
    final src = all.where((i) => i.id == e.instanceId).firstOrNull;
    if (src == null) return;
    final now = clock.now();
    await reminders.saveInstance(
      src.copyWith(status: ReminderStatus.fired, updatedAt: now),
    );
    var snoozed = policy.snooze(src, delay, now, IdGen.newId);
    try {
      final pid = await reminderGateway.scheduleCalendarReminder(
        _payloadFor(card, snoozed),
      );
      snoozed = snoozed.copyWith(platformReminderId: pid);
    } on AppFailure catch (f) {
      snoozed = snoozed.copyWith(
        status: ReminderStatus.failed,
        failureReason: f.code.name,
      );
    }
    await reminders.saveInstance(snoozed);
  }

  /// 启动 reconciliation：
  /// 1) 清理已过期但仍标记 scheduled 的实例；
  /// 2) 检查未来实例是否有平台 ID，缺失则补建。
  Future<void> reconcile() async {
    final now = clock.now();
    final scheduled = await reminders.allScheduledInstances();
    for (final inst in scheduled) {
      if (!inst.triggerAt.isAfter(now)) {
        await reminders.saveInstance(
          inst.copyWith(status: ReminderStatus.fired, updatedAt: now),
        );
        continue;
      }
      if (inst.platformReminderId == null) {
        final card = await cards.findById(inst.cardId);
        if (card == null || card.status != CardStatus.active) continue;
        try {
          final pid = await reminderGateway.scheduleCalendarReminder(
            _payloadFor(card, inst),
          );
          await reminders.saveInstance(
            inst.copyWith(platformReminderId: pid, updatedAt: now),
          );
        } on AppFailure catch (f) {
          AppLog.w('reconcile', '补建提醒失败: ${f.code.name}');
        }
      }
    }
  }
}
