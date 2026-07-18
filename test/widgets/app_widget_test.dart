import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/app/app_controller.dart';
import 'package:freshcue/app/freshcue_app.dart';
import 'package:freshcue/core/clock/clock.dart';
import 'package:freshcue/core/utils/id_gen.dart';
import 'package:freshcue/domain/entities/temporal_card.dart';
import 'package:freshcue/domain/enums/enums.dart';
import 'package:freshcue/features/review/review_page.dart';
import 'package:freshcue/platform/gateways.dart';
import 'package:freshcue/platform/mock_gateways.dart';

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
      liveView: MockLiveViewGateway(),
      sandboxDir: '/tmp/freshcue_test_sandbox',
    );
  });

  Future<TemporalCard> seedCard({bool sensitive = false}) async {
    final card = TemporalCard(
      id: IdGen.newId(),
      title: '校园创新体验日',
      category: sensitive ? CardCategory.temporarySecret : CardCategory.event,
      status: CardStatus.active,
      secretValue: sensitive ? 'A7281' : null,
      deadlineAt: DateTime(2026, 7, 20, 18, 0),
      eventStartAt: DateTime(2026, 7, 25, 14, 0),
      isSensitive: sensitive,
      createdAt: now,
      updatedAt: now,
    );
    await controller.cards.save(card);
    await controller.refresh();
    return card;
  }

  Widget app() =>
      FreshCueApp(controller: controller, showOnboarding: false);

  testWidgets('首页空状态展示操作提示', (tester) async {
    await controller.refresh();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('还没有时效卡片'), findsOneWidget);
    expect(find.textContaining('系统分享'), findsOneWidget);
    expect(find.text('导入截图'), findsOneWidget);
  });

  testWidgets('首页有数据状态显示卡片与时间语义', (tester) async {
    await seedCard();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('校园创新体验日'), findsOneWidget);
    expect(find.textContaining('截止还有'), findsOneWidget);
  });

  testWidgets('Mock 模式显示模拟能力横幅', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('模拟能力模式'), findsOneWidget);
  });

  testWidgets('敏感内容在列表中遮罩', (tester) async {
    await seedCard(sensitive: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('A7281'), findsNothing);
    expect(find.textContaining('A•••1'), findsOneWidget);
  });

  testWidgets('确认页：低置信度提示 + 多时间分组 + 提醒预览', (tester) async {
    controller.importManualText(
      '校园创新体验日\n报名截止：7月20日 18:00\n活动时间：7月25日 14:00\n本周五 18:00 交材料',
    );
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ReviewPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('截止'), findsWidgets);
    expect(find.textContaining('活动开始'), findsWidgets);
    expect(find.text('请确认'), findsWidgets); // 本周五已过去 → 需要确认
    expect(find.textContaining('将创建'), findsOneWidget);
  });

  testWidgets('确认草稿后首页出现卡片，权限拒绝时提示未启用', (tester) async {
    reminderGateway.permissionGranted = false;
    controller.importManualText('报名截止：7月20日 18:00 交材料');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final (id, failures) = await controller.confirmDraft(
      title: '交材料',
      category: CardCategory.deadline,
      anchors: controller.pendingDraft!.draft.suggestedAnchors,
    );
    expect(failures, -1); // 权限被拒：卡片保存、提醒未启用
    expect(id, isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('交材料'), findsOneWidget);
    expect(reminderGateway.scheduled, isEmpty);
  });

  testWidgets('深色模式渲染无异常', (tester) async {
    await seedCard();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: app(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('校园创新体验日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大字体（1.6x）不溢出', (tester) async {
    await seedCard();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(1.6),
        ),
        child: app(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('过期卡片进入过期箱并可恢复', (tester) async {
    final card = TemporalCard(
      id: 'exp1',
      title: '已过期讲座',
      category: CardCategory.event,
      status: CardStatus.active,
      eventStartAt: now.subtract(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
    );
    await controller.cards.save(card);
    await controller.refresh();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // 首页不显示过期卡
    expect(find.text('已过期讲座'), findsNothing);
    // 切到过期箱
    await tester.tap(find.text('过期箱'));
    await tester.pumpAndSettle();
    expect(find.text('已过期讲座'), findsOneWidget);
    expect(find.text('恢复并重设时间'), findsOneWidget);
  });

  testWidgets('通知 complete 行为使卡片完成', (tester) async {
    final card = await seedCard();
    await controller.start();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    reminderGateway.emitAction(
      ReminderActionEvent(
        action: ReminderActionType.complete,
        cardId: card.id,
        instanceId: '',
      ),
    );
    await tester.pumpAndSettle();
    expect((await controller.cards.findById(card.id))!.status,
        CardStatus.completed,);
  });
}
