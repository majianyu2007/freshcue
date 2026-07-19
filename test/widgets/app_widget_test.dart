import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/app/app_controller.dart';
import 'package:freshcue/app/freshcue_app.dart';
import 'package:freshcue/core/clock/clock.dart';
import 'package:freshcue/core/errors/app_failure.dart';
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
  late MockCalendarGateway calendarGateway;
  late MockFormGateway formGateway;
  late AppController controller;

  setUp(() {
    clock = FixedClock(now);
    reminderGateway = MockReminderGateway(clock);
    calendarGateway = MockCalendarGateway();
    formGateway = MockFormGateway();
    controller = createMemoryAppController(
      clock: clock,
      ocr: MockOcrGateway(),
      share: MockShareGateway(),
      reminderGateway: reminderGateway,
      calendarGateway: calendarGateway,
      formGateway: formGateway,
      sandboxDir: '/tmp/freshcue_test_sandbox',
    );
  });

  Future<TemporalCard> seedCard({
    bool sensitive = false,
    DateTime? deadlineAt,
  }) async {
    final card = TemporalCard(
      id: IdGen.newId(),
      title: '校园创新体验日',
      category: sensitive ? CardCategory.temporarySecret : CardCategory.event,
      status: CardStatus.active,
      secretValue: sensitive ? 'A7281' : null,
      deadlineAt: deadlineAt ?? DateTime(2026, 7, 20, 18, 0),
      eventStartAt: DateTime(2026, 7, 25, 14, 0),
      isSensitive: sensitive,
      createdAt: now,
      updatedAt: now,
    );
    await controller.cards.save(card);
    await controller.refresh();
    return card;
  }

  Widget app() => FreshCueApp(controller: controller, showOnboarding: false);

  testWidgets('首页空状态展示操作提示', (tester) async {
    await controller.refresh();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('还没有时效卡片'), findsOneWidget);
    expect(find.textContaining('系统分享'), findsOneWidget);
    expect(find.text('拍一张'), findsOneWidget);
  });

  testWidgets('更多导入不再展示已失效的演示样例', (tester) async {
    await controller.refresh();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    expect(find.text('试试示例截图'), findsOneWidget);
    expect(find.text('手动输入文字'), findsOneWidget);
    expect(find.text('演示样例'), findsNothing);
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

  testWidgets('设置首页只保留可进入的真实入口', (tester) async {
    await controller.refreshOcrModelStatus();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('文字识别'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('过期整理'), findsOneWidget);
    expect(find.text('隐私与数据'), findsOneWidget);
    expect(find.text('发送即时通知'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('关于截期'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('关于截期'), findsOneWidget);

    await tester.tap(find.text('文字识别'));
    await tester.pumpAndSettle();
    expect(find.text('文字识别已就绪'), findsOneWidget);
    expect(find.textContaining('模拟 OCR'), findsOneWidget);
  });

  testWidgets('外观与过期整理可修改并持久化', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);
    expect(await controller.settings.get('theme_mode'), 'dark');

    await tester.tap(find.text('过期整理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留 30 天'));
    await tester.pumpAndSettle();
    expect(controller.autoArchiveDays, 30);
    expect(await controller.settings.get('auto_archive_days'), '30');
  });

  testWidgets('通知权限行打开系统设置且安静时段可关闭', (tester) async {
    controller.notificationPermissionGranted = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('通知权限'));
    await tester.pumpAndSettle();
    expect(reminderGateway.notificationSettingsOpenCount, 1);

    await tester.tap(find.text('避开夜间提醒'));
    await tester.pumpAndSettle();
    expect(controller.quietHoursEnabled, isFalse);
    expect(await controller.settings.get('quiet_hours_enabled'), '0');
    expect(find.text('通知测试'), findsOneWidget);
  });

  testWidgets('默认提醒方式和提醒次数可修改并持久化', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('默认方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统日程'));
    await tester.pumpAndSettle();
    expect(controller.defaultDeliveryMode, DeliveryMode.systemCalendar);
    expect(
      await controller.settings.get('default_delivery_mode'),
      DeliveryMode.systemCalendar.name,
    );

    await tester.tap(find.text('提醒次数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多提醒'));
    await tester.pumpAndSettle();
    expect(controller.reminderFrequency, ReminderFrequency.thorough);
    expect(
      await controller.settings.get('reminder_frequency'),
      ReminderFrequency.thorough.name,
    );
  });

  testWidgets('关于页面展示产品信息而不是提醒调试工具', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('关于截期'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('关于截期'));
    await tester.pumpAndSettle();

    expect(find.text('截期 FreshCue'), findsOneWidget);
    expect(find.textContaining('把截图变成会提醒'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.textContaining('5 分钟演示提醒'), findsNothing);
  });

  testWidgets('隐私开关会实际切换敏感码显示', (tester) async {
    await seedCard(sensitive: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私与数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接显示敏感码'));
    await tester.pumpAndSettle();
    expect(controller.showSensitiveCodes, isFalse);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A•••1'), findsOneWidget);
    expect(find.textContaining('A7281'), findsNothing);
  });

  testWidgets('取件码在应用列表中直接显示', (tester) async {
    await seedCard(sensitive: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('A7281'), findsOneWidget);
    expect(find.textContaining('A•••1'), findsNothing);
  });

  test('服务卡片最多发布3张未完成卡片并直接显示敏感码', () async {
    await seedCard(deadlineAt: DateTime(2026, 7, 19, 18));
    final sensitive = await seedCard(
      sensitive: true,
      deadlineAt: DateTime(2026, 7, 20, 18),
    );
    await seedCard(deadlineAt: DateTime(2026, 7, 21, 18));
    await seedCard(deadlineAt: DateTime(2026, 7, 22, 18));
    await Future<void>.delayed(Duration.zero);

    expect(formGateway.cards, hasLength(3));
    final snapshot = formGateway.cards.singleWhere(
      (card) => card.id == sensitive.id,
    );
    expect(snapshot.title, '校园创新体验日');
    expect(snapshot.timeLabel, contains('A7281'));
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
    expect(find.textContaining('日期可能有偏差'), findsWidgets);
    expect(find.textContaining('截期会提醒'), findsOneWidget);
  });

  testWidgets('确认页选择系统日程后只创建日程', (tester) async {
    await controller.setDefaultDeliveryMode(DeliveryMode.systemCalendar);
    controller.importManualText('报名截止：7月20日 18:00 交材料');
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ReviewPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('两种方式不会同时开启'), findsOneWidget);
    expect(find.text('保存并加入系统日程'), findsOneWidget);
    await tester.tap(find.text('保存并加入系统日程'));
    await tester.pumpAndSettle();

    final saved = controller.activeCards.single;
    expect(saved.deliveryMode, DeliveryMode.systemCalendar);
    expect(saved.calendarEventId, isNotNull);
    expect(calendarGateway.events, hasLength(1));
    expect(reminderGateway.scheduled, isEmpty);
  });

  testWidgets('确认页显示实际 OCR provider', (tester) async {
    final imported = await tester.runAsync(
      () => controller.importFromBytes(
        tinyPngBytes(),
        source: ImportSource.gallery,
        displayName: 'OCR provider test.png',
      ),
    );
    expect(imported, isTrue, reason: controller.importFailure.toString());
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ReviewPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('识别详情'));
    await tester.pumpAndSettle();
    expect(find.text('模拟 OCR'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.cancelImport();
  });

  testWidgets('OCR 全部失败仍进入可编辑确认页', (tester) async {
    controller = createMemoryAppController(
      clock: clock,
      ocr: _FailingOcrGateway(),
      share: MockShareGateway(),
      reminderGateway: reminderGateway,
      calendarGateway: MockCalendarGateway(),
      formGateway: MockFormGateway(),
      sandboxDir: '/tmp/freshcue_test_sandbox',
    );
    final imported = await tester.runAsync(
      () => controller.importFromBytes(
        tinyPngBytes(),
        source: ImportSource.gallery,
      ),
    );
    expect(imported, isTrue);
    expect(controller.pendingDraft, isNotNull);
    expect(controller.pendingDraft!.ocrProvider, OcrProvider.none);
    expect(controller.importFailure?.code, FailureCode.ocrFailed);

    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ReviewPage(controller: controller)),
    );
    await tester.pump();
    expect(find.textContaining('这次没认全'), findsOneWidget);
    expect(find.byType(TextField), findsAtLeast(1));
    await tester.dragUntilVisible(
      find.text('添加时间'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    expect(find.text('添加时间'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.cancelImport();
  });

  testWidgets('确认草稿后首页出现卡片，权限拒绝时提示未启用', (tester) async {
    reminderGateway.permissionGranted = false;
    controller.importManualText('报名截止：7月20日 18:00 交材料');

    final (id, failures) = await controller.confirmDraft(
      title: '交材料',
      category: CardCategory.deadline,
      anchors: controller.pendingDraft!.draft.suggestedAnchors,
    );
    expect(failures.permissionDenied, isTrue);
    expect(id, isNotEmpty);
    await tester.pumpWidget(app());
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
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
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
    // 切到归档
    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();
    expect(find.text('已过期讲座'), findsOneWidget);
    expect(find.text('恢复并重设时间'), findsOneWidget);
  });

  testWidgets('冷启动分享草稿在首帧自动打开确认页', (tester) async {
    controller.importManualText('报名截止：7月20日 18:00');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('确认内容'), findsOneWidget);
  });

  testWidgets('冷启动通知深链在首帧打开目标卡片', (tester) async {
    final card = await seedCard();
    controller.pendingRoute.value = 'freshcue://card/${card.id}';
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('提醒'), findsOneWidget);
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
    expect(
      (await controller.cards.findById(card.id))!.status,
      CardStatus.completed,
    );
  });
}

class _FailingOcrGateway implements OcrGateway {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<OcrModelStatus> getModelStatus() async =>
      const OcrModelStatus.unavailable();

  @override
  Future<OcrModelStatus> downloadModels(OcrDownloadSource source) async =>
      const OcrModelStatus.unavailable();

  @override
  Future<OcrModelStatus> deleteModels() async =>
      const OcrModelStatus.unavailable();

  @override
  Future<OcrResult> recognizeImage({
    required String sandboxPath,
    List<String> languageHints = const ['zh-Hans'],
    bool detectOrientation = true,
  }) async {
    throw const AppFailure(FailureCode.ocrFailed);
  }
}
