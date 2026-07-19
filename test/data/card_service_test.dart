import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/core/clock/clock.dart';
import 'package:freshcue/core/utils/id_gen.dart';
import 'package:freshcue/data/card_service.dart';
import 'package:freshcue/data/database/image_asset_service.dart';
import 'package:freshcue/data/repositories/memory_repositories.dart';
import 'package:freshcue/domain/entities/temporal_card.dart';
import 'package:freshcue/domain/enums/enums.dart';
import 'package:freshcue/domain/services/reminder_policy.dart';
import 'package:freshcue/platform/gateways.dart';
import 'package:freshcue/platform/mock_gateways.dart';

void main() {
  final now = DateTime(2026, 7, 18, 10, 0);
  late FixedClock clock;
  late MemoryCardRepository cards;
  late MemoryReminderRepository reminders;
  late MockReminderGateway gateway;
  late MockCalendarGateway calendarGateway;
  late CardService service;

  setUp(() {
    clock = FixedClock(now);
    cards = MemoryCardRepository();
    reminders = MemoryReminderRepository();
    gateway = MockReminderGateway(clock);
    calendarGateway = MockCalendarGateway();
    service = CardService(
      cards: cards,
      assets: MemoryAssetRepository(),
      ocrBlocks: MemoryOcrBlockRepository(),
      reminders: reminders,
      reminderGateway: gateway,
      calendarGateway: calendarGateway,
      assetService: ImageAssetService(sandboxDir: '/tmp/unused'),
      clock: clock,
    );
  });

  TemporalCard card() => TemporalCard(
    id: 'c1',
    title: '测试活动',
    category: CardCategory.event,
    status: CardStatus.draft,
    deadlineAt: DateTime(2026, 7, 20, 18, 0),
    eventStartAt: DateTime(2026, 7, 25, 14, 0),
    createdAt: now,
    updatedAt: now,
  );

  test('确认卡片：状态 active + 全部提醒调度成功', () async {
    final c = card();
    final plans = const ReminderPolicy().defaultPlans(c, IdGen.newId);
    final result = await service.confirmCard(c, plans);
    expect(result.failures, 0);
    expect((await cards.findById('c1'))!.status, CardStatus.active);
    final instances = await reminders.instancesByCard('c1');
    expect(instances, isNotEmpty);
    expect(instances.every((i) => i.platformReminderId != null), isTrue);
    expect(gateway.scheduled.length, instances.length);
  });

  test('选择系统日程：创建事件且不再创建应用提醒', () async {
    final c = card().copyWith(deliveryMode: DeliveryMode.systemCalendar);
    final plans = const ReminderPolicy().defaultPlans(c, IdGen.newId);

    final result = await service.confirmCard(c, plans);

    expect(result.succeeded, isTrue);
    expect(gateway.scheduled, isEmpty);
    expect(await reminders.instancesByCard('c1'), isEmpty);
    expect(calendarGateway.events, hasLength(1));
    final saved = (await cards.findById('c1'))!;
    expect(saved.calendarEventId, isNotNull);
    final event = calendarGateway.events[saved.calendarEventId]!;
    expect(event.title, '测试活动');
    expect(event.startAt, DateTime(2026, 7, 25, 14));
    expect(event.reminderMinutes, containsAll(<int>[10, 1440]));
  });

  test('系统日程：改时间更新原事件，删卡片同步删除', () async {
    final c = card().copyWith(deliveryMode: DeliveryMode.systemCalendar);
    await service.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );
    final saved = (await cards.findById('c1'))!;
    final eventId = saved.calendarEventId!;

    final edited = saved.copyWith(eventStartAt: DateTime(2026, 7, 26, 9));
    final result = await service.rebuildDelivery(edited);

    expect(result.succeeded, isTrue);
    expect(calendarGateway.events, hasLength(1));
    expect(calendarGateway.events[eventId]!.startAt, DateTime(2026, 7, 26, 9));

    await service.deleteCard('c1');
    expect(calendarGateway.events, isEmpty);
    expect(await cards.findById('c1'), isNull);
  });

  test('系统日程权限被拒：保留卡片并返回可恢复状态', () async {
    calendarGateway.permissionGranted = false;
    final c = card().copyWith(deliveryMode: DeliveryMode.systemCalendar);

    final result = await service.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );

    expect(result.permissionDenied, isTrue);
    expect((await cards.findById('c1'))!.status, CardStatus.active);
    expect(calendarGateway.events, isEmpty);
    expect(gateway.scheduled, isEmpty);
  });

  test('敏感码在通知与锁屏载荷中直接显示', () async {
    final c = card().copyWith(secretValue: '6-2-8519', isSensitive: true);
    final plans = const ReminderPolicy().defaultPlans(c, IdGen.newId);
    await service.confirmCard(c, plans);

    expect(gateway.scheduled, isNotEmpty);
    expect(
      gateway.scheduled.values.every(
        (payload) =>
            payload.title == '测试活动' &&
            payload.body.contains('6-2-8519') &&
            !payload.hideContentOnLockScreen,
      ),
      isTrue,
    );
  });

  test('关闭直接显示后通知遮罩敏感码并隐藏锁屏内容', () async {
    service.showSensitiveCodes = false;
    final c = card().copyWith(secretValue: '6-2-8519', isSensitive: true);
    final plans = const ReminderPolicy().defaultPlans(c, IdGen.newId);
    await service.confirmCard(c, plans);

    expect(gateway.scheduled, isNotEmpty);
    expect(
      gateway.scheduled.values.every(
        (payload) =>
            payload.title == '截期提醒' &&
            !payload.body.contains('6-2-8519') &&
            payload.hideContentOnLockScreen,
      ),
      isTrue,
    );
  });

  test('编辑时间：旧平台提醒被取消，新提醒重建', () async {
    final c = card();
    final plans = const ReminderPolicy().defaultPlans(c, IdGen.newId);
    await service.confirmCard(c, plans);
    final oldIds = gateway.scheduled.keys.toSet();

    final edited = (await cards.findById(
      'c1',
    ))!.copyWith(eventStartAt: DateTime(2026, 7, 26, 9, 0));
    await service.rebuildDelivery(edited);

    expect(gateway.scheduled.keys.toSet().intersection(oldIds), isEmpty);
    final instances = await reminders.instancesByCard('c1');
    expect(
      instances.any(
        (i) => i.triggerAt == DateTime(2026, 7, 25, 9, 0), // 前1天
      ),
      isTrue,
    );
  });

  test('删除卡片：先取消平台提醒再清库', () async {
    final c = card();
    await service.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );
    expect(gateway.scheduled, isNotEmpty);
    await service.deleteCard('c1');
    expect(gateway.scheduled, isEmpty);
    expect(await cards.findById('c1'), isNull);
    expect(await reminders.instancesByCard('c1'), isEmpty);
  });

  test('通知 complete 行为：卡片完成且提醒取消', () async {
    final c = card();
    await service.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );
    await service.handleAction(
      const ReminderActionEvent(
        action: ReminderActionType.complete,
        cardId: 'c1',
        instanceId: '',
      ),
    );
    expect((await cards.findById('c1'))!.status, CardStatus.completed);
    expect(gateway.scheduled, isEmpty);
  });

  test('snooze 行为：新实例记录来源并调度', () async {
    final c = card();
    await service.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );
    final first = (await reminders.instancesByCard('c1')).first;
    await service.handleAction(
      ReminderActionEvent(
        action: ReminderActionType.snooze10m,
        cardId: 'c1',
        instanceId: first.id,
      ),
    );
    final all = await reminders.instancesByCard('c1');
    final snoozed = all
        .where((i) => i.snoozedFromInstanceId == first.id)
        .single;
    expect(snoozed.triggerAt, now.add(const Duration(minutes: 10)));
  });

  test('reconciliation：过期 scheduled 实例被标记 fired', () async {
    final c = card();
    await service.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );
    clock.advance(const Duration(days: 3)); // 越过 7月20日截止前提醒
    await service.reconcile();
    final all = await reminders.instancesByCard('c1');
    expect(
      all
          .where((i) => !i.triggerAt.isAfter(clock.now()))
          .every((i) => i.status == ReminderStatus.fired),
      isTrue,
    );
  });

  test('调度失败时实例标记 failed 并返回失败数（不假装成功）', () async {
    gateway.permissionGranted = false; // isAvailable 仍 true，但让调度抛错
    final failing = _FailingGateway();
    final svc = CardService(
      cards: cards,
      assets: MemoryAssetRepository(),
      ocrBlocks: MemoryOcrBlockRepository(),
      reminders: reminders,
      reminderGateway: failing,
      calendarGateway: calendarGateway,
      assetService: ImageAssetService(sandboxDir: '/tmp/unused'),
      clock: clock,
    );
    final c = card();
    final result = await svc.confirmCard(
      c,
      const ReminderPolicy().defaultPlans(c, IdGen.newId),
    );
    expect(result.failures, greaterThan(0));
    final all = await reminders.instancesByCard('c1');
    expect(all.every((i) => i.status == ReminderStatus.failed), isTrue);
    expect(all.first.failureReason, isNotNull);
  });

  test('通知深链 opened 遇到不存在的 cardId → 安全失败（不抛异常）', () async {
    // 原生 ReminderPlugin 仅发 'opened'；卡片可能已被删除。
    await expectLater(
      service.handleAction(
        const ReminderActionEvent(
          action: ReminderActionType.opened,
          cardId: 'does-not-exist',
          instanceId: '',
        ),
      ),
      completes,
    );
  });

  test('snooze 行为遇到不存在的 cardId → 安全返回（不抛异常）', () async {
    await expectLater(
      service.handleAction(
        const ReminderActionEvent(
          action: ReminderActionType.snooze10m,
          cardId: 'does-not-exist',
          instanceId: 'x',
        ),
      ),
      completes,
    );
  });
}

class _FailingGateway extends MockReminderGateway {
  _FailingGateway() : super(FixedClock(DateTime(2026)));

  @override
  Future<bool> isAvailable() async => false;
}
