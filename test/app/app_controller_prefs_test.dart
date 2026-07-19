import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/app/app_controller.dart';
import 'package:freshcue/core/clock/clock.dart';
import 'package:freshcue/domain/entities/temporal_card.dart';
import 'package:freshcue/domain/enums/enums.dart';
import 'package:freshcue/platform/gateways.dart';
import 'package:freshcue/platform/mock_gateways.dart';

/// 通用设置与深链路由行为。
void main() {
  final now = DateTime(2026, 7, 18, 10, 0);
  late FixedClock clock;
  late MockReminderGateway reminderGateway;
  late AppController controller;

  setUp(() {
    clock = FixedClock(now);
    reminderGateway = MockReminderGateway(clock);
    controller = createMemoryAppController(
      clock: clock,
      ocr: MockOcrGateway(),
      share: MockShareGateway(),
      reminderGateway: reminderGateway,
      calendarGateway: MockCalendarGateway(),
      formGateway: MockFormGateway(),
      sandboxDir: '/tmp/freshcue_prefs_test_sandbox',
    );
  });

  TemporalCard card(String id, {DateTime? expiresAt}) => TemporalCard(
    id: id,
    title: '卡片$id',
    category: CardCategory.generic,
    status: CardStatus.active,
    expiresAt: expiresAt,
    createdAt: now,
    updatedAt: now,
  );

  test('主题与整理期限从设置读取，写入后持久化', () async {
    await controller.settings.set('theme_mode', 'dark');
    await controller.settings.set('auto_archive_days', '3');
    await controller.start();
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.autoArchiveDays, 3);

    await controller.setThemeMode(ThemeMode.light);
    expect(await controller.settings.get('theme_mode'), 'light');
  });

  test('过期超过期限的卡片启动时自动归档，期限内的保留', () async {
    await controller.cards.save(
      card('old', expiresAt: now.subtract(const Duration(days: 10))),
    );
    await controller.cards.save(
      card('recent', expiresAt: now.subtract(const Duration(days: 2))),
    );
    await controller.cards.save(
      card('future', expiresAt: now.add(const Duration(days: 2))),
    );
    await controller.start(); // 默认 7 天

    expect(
      (await controller.cards.findById('old'))!.status,
      CardStatus.archived,
    );
    expect(
      (await controller.cards.findById('recent'))!.status,
      CardStatus.active,
    );
    expect(
      (await controller.cards.findById('future'))!.status,
      CardStatus.active,
    );
    expect(controller.expiredCards.map((c) => c.id), ['recent']);
  });

  test('关闭自动整理后过期卡片一直保留', () async {
    await controller.settings.set('auto_archive_days', '0');
    await controller.cards.save(
      card('old', expiresAt: now.subtract(const Duration(days: 30))),
    );
    await controller.start();
    expect((await controller.cards.findById('old'))!.status, CardStatus.active);
  });

  test('route 深链动作只跳转，不触发卡片副作用', () async {
    await controller.start();
    reminderGateway.emitAction(
      const ReminderActionEvent(
        action: ReminderActionType.route,
        cardId: '',
        instanceId: '',
        uri: 'freshcue://import/camera',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.pendingRoute.value, 'freshcue://import/camera');
  });
}
