import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:sqflite_common/sqlite_api.dart' show Database;

import '../core/clock/clock.dart';
import '../core/errors/app_failure.dart';
import '../core/logging/app_log.dart';
import '../core/utils/id_gen.dart';
import '../core/utils/redactor.dart';
import '../data/card_service.dart';
import '../data/database/image_asset_service.dart';
import '../data/repositories/memory_repositories.dart';
import '../data/repositories/sql_repositories.dart';
import '../domain/entities/reminder.dart';
import '../domain/entities/source_asset.dart';
import '../domain/entities/temporal_card.dart';
import '../domain/enums/enums.dart';
import '../domain/parser/screenshot_parser.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/freshness_policy.dart';
import '../domain/services/reminder_policy.dart';
import '../platform/capabilities.dart';
import '../platform/gateways.dart';

/// 导入流程阶段（处理页展示，不伪造百分比）。
enum ImportStage {
  idle,
  reading,
  recognizing,
  analyzing,
  preparing,
  done,
  failed,
}

/// 待确认草稿的完整上下文。
class DraftContext {
  DraftContext({
    required this.draft,
    required this.asset,
    required this.blocks,
    required this.capturedAt,
    required this.ocrProvider,
    this.duplicateOfCardId,
    this.additionalDrafts = const [],
  });

  ParsedDraft draft;
  final List<ParsedDraft> additionalDrafts;
  List<ParsedDraft> get drafts => [draft, ...additionalDrafts];
  final SourceAsset? asset;
  final List<OcrBlock> blocks;
  final DateTime capturedAt;
  final OcrProvider ocrProvider;

  /// 相同 SHA-256 的已有卡片（提示用户而非静默丢弃）。
  final String? duplicateOfCardId;
}

/// 全局应用控制器（ChangeNotifier，单页面级别足够，不引入状态框架）。
class AppController extends ChangeNotifier {
  AppController({
    required this.cards,
    required this.assets,
    required this.ocrBlocks,
    required this.reminders,
    required this.settings,
    required this.cardService,
    required this.assetService,
    required this.ocr,
    required this.share,
    required this.reminderGateway,
    required this.calendarGateway,
    required this.formGateway,
    required this.clock,
    required this.usingMockPlatform,
    this.capabilities = const PlatformCapabilities.unbridged(),
  }) {
    _parser = ScreenshotParser();
  }

  final CardRepository cards;
  final AssetRepository assets;
  final OcrBlockRepository ocrBlocks;
  final ReminderRepository reminders;
  final SettingsRepository settings;
  final CardService cardService;
  final ImageAssetService assetService;
  final OcrGateway ocr;
  final ShareGateway share;
  final ReminderGateway reminderGateway;
  final CalendarGateway calendarGateway;
  final FormGateway formGateway;
  final Clock clock;
  final bool usingMockPlatform;

  /// 原生能力握手快照（诊断页展示真实 compiled/available/reason）。
  final PlatformCapabilities capabilities;

  late final ScreenshotParser _parser;
  final FreshnessPolicy freshness = const FreshnessPolicy();
  ReminderPolicy get reminderPolicy => cardService.policy;

  List<TemporalCard> activeCards = [];
  List<TemporalCard> expiredCards = [];
  List<TemporalCard> doneCards = [];

  ImportStage importStage = ImportStage.idle;
  AppFailure? importFailure;
  DraftContext? pendingDraft;
  bool? notificationPermissionGranted;
  bool requestingNotificationPermission = false;
  bool onboardingComplete = false;
  OcrModelStatus ocrModelStatus = const OcrModelStatus.unavailable();
  bool downloadingOcrModels = false;
  bool quietHoursEnabled = true;
  int quietStartHour = 23;
  int quietEndHour = 7;
  bool showSensitiveCodes = true;
  DeliveryMode defaultDeliveryMode = DeliveryMode.appReminder;
  ReminderFrequency reminderFrequency = ReminderFrequency.standard;
  ThemeMode themeMode = ThemeMode.system;

  /// 过期卡片在过期箱停留 N 天后自动收进归档；0 表示不自动整理。
  int autoArchiveDays = 7;

  Future<void> refreshOcrModelStatus() async {
    ocrModelStatus = await ocr.getModelStatus();
    notifyListeners();
  }

  Future<void> downloadOcrModels(OcrDownloadSource source) async {
    if (downloadingOcrModels) return;
    downloadingOcrModels = true;
    notifyListeners();
    final progressTimer = Timer.periodic(const Duration(milliseconds: 400), (
      _,
    ) async {
      try {
        ocrModelStatus = await ocr.getModelStatus();
        notifyListeners();
      } on Object {
        // 下载结果负责报告错误；轮询只刷新进度。
      }
    });
    try {
      ocrModelStatus = await ocr.downloadModels(source);
    } finally {
      progressTimer.cancel();
      downloadingOcrModels = false;
      notifyListeners();
    }
  }

  Future<void> deleteOcrModels() async {
    ocrModelStatus = await ocr.deleteModels();
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await settings.set('onboarding_complete', '1');
    onboardingComplete = true;
    notifyListeners();
  }

  Future<bool> requestNotificationPermission() async {
    if (requestingNotificationPermission) {
      return notificationPermissionGranted ?? false;
    }
    requestingNotificationPermission = true;
    notifyListeners();
    final granted = await reminderGateway.requestPermissionIfNeeded();
    notificationPermissionGranted = granted;
    requestingNotificationPermission = false;
    notifyListeners();
    return granted;
  }

  Future<void> openNotificationSettings() async {
    await reminderGateway.openNotificationSettings();
    notificationPermissionGranted = await reminderGateway
        .getNotificationPermissionStatus();
    notifyListeners();
  }

  Future<int> updateQuietHours({
    required bool enabled,
    required int startHour,
    required int endHour,
  }) async {
    quietHoursEnabled = enabled;
    quietStartHour = startHour;
    quietEndHour = endHour;
    _applyPreferences();
    await settings.set('quiet_hours_enabled', enabled ? '1' : '0');
    await settings.set('quiet_start_hour', '$startHour');
    await settings.set('quiet_end_hour', '$endHour');
    var failures = 0;
    for (final card in activeCards) {
      if (card.deliveryMode == DeliveryMode.appReminder) {
        failures += (await cardService.rebuildDelivery(card)).failures;
      }
    }
    await refresh();
    return failures;
  }

  Future<void> setShowSensitiveCodes(bool value) async {
    showSensitiveCodes = value;
    _applyPreferences();
    await settings.set('show_sensitive_codes', value ? '1' : '0');
    await refresh();
  }

  Future<void> setDefaultDeliveryMode(DeliveryMode mode) async {
    defaultDeliveryMode = mode;
    await settings.set('default_delivery_mode', mode.name);
    notifyListeners();
  }

  Future<void> setReminderFrequency(ReminderFrequency frequency) async {
    reminderFrequency = frequency;
    _applyPreferences();
    await settings.set('reminder_frequency', frequency.name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await settings.set('theme_mode', mode.name);
    notifyListeners();
  }

  Future<void> setAutoArchiveDays(int days) async {
    autoArchiveDays = days;
    await settings.set('auto_archive_days', '$days');
    await _autoTidy();
    await refresh();
  }

  /// 把过期超过 [autoArchiveDays] 天的卡片自动收进归档。
  Future<void> _autoTidy() async {
    if (autoArchiveDays <= 0) return;
    final now = clock.now();
    final active = await cards.listByStatus({CardStatus.active});
    for (final card in active) {
      final expiry = card.effectiveExpiry;
      if (expiry == null) continue;
      if (now.difference(expiry).inDays >= autoArchiveDays) {
        try {
          await cardService.archive(card.id);
        } on AppFailure catch (failure) {
          AppLog.w('tidy', '自动归档失败: ${failure.code.name}');
        }
      }
    }
  }

  String displaySecret(String secret) =>
      showSensitiveCodes ? secret : Redactor.maskSecret(secret);

  String displayTitle(TemporalCard card) =>
      card.isSensitive && !showSensitiveCodes ? '时效提醒' : card.title;

  Future<void> sendInstantNotification() => reminderGateway
      .publishInstantNotification(title: '截期通知已就绪', body: '后续到期提醒会显示在这里。');

  StreamSubscription<SharedItem>? _shareSub;
  StreamSubscription<ReminderActionEvent>? _actionSub;

  /// 深链/通知点击的待跳转卡片。
  final ValueNotifier<String?> pendingRoute = ValueNotifier(null);

  Future<void> start() async {
    onboardingComplete = await settings.get('onboarding_complete') == '1';
    quietHoursEnabled = await settings.get('quiet_hours_enabled') != '0';
    quietStartHour =
        int.tryParse(await settings.get('quiet_start_hour') ?? '') ?? 23;
    quietEndHour =
        int.tryParse(await settings.get('quiet_end_hour') ?? '') ?? 7;
    showSensitiveCodes = await settings.get('show_sensitive_codes') != '0';
    defaultDeliveryMode = DeliveryMode.fromName(
      await settings.get('default_delivery_mode') ?? '',
    );
    reminderFrequency = ReminderFrequency.fromName(
      await settings.get('reminder_frequency') ?? '',
    );
    final rawThemeMode = await settings.get('theme_mode');
    themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == rawThemeMode,
      orElse: () => ThemeMode.system,
    );
    autoArchiveDays =
        int.tryParse(await settings.get('auto_archive_days') ?? '') ?? 7;
    _applyPreferences();
    notificationPermissionGranted = await reminderGateway
        .getNotificationPermissionStatus();
    await refreshOcrModelStatus();
    await _autoTidy();
    await refresh();
    await cardService.reconcile();
    _shareSub = share.sharedItems.listen(_onShared);
    _actionSub = reminderGateway.actions.listen(_onAction);
    final initial = await _safeInitialShare();
    if (initial != null) {
      await share.consumeInitialShare(initial.id);
      await importFromBytes(
        initial.bytes,
        source: ImportSource.share,
        displayName: initial.displayName,
      );
    }
  }

  void _applyPreferences() {
    cardService.policy = ReminderPolicy(
      quietHoursEnabled: quietHoursEnabled,
      quietStartHour: quietStartHour,
      quietEndHour: quietEndHour,
      frequency: reminderFrequency,
    );
    cardService.showSensitiveCodes = showSensitiveCodes;
  }

  Future<SharedItem?> _safeInitialShare() async {
    try {
      return await share.getInitialShare();
    } on AppFailure catch (f) {
      AppLog.w('share', '读取冷启动分享失败: ${f.code.name}');
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_shareSub?.cancel());
    unawaited(_actionSub?.cancel());
    super.dispose();
  }

  Future<void> refresh() async {
    final now = clock.now();
    final active = await cards.listByStatus({CardStatus.active});
    activeCards =
        active
            .where((c) => freshness.evaluate(c, now) != Freshness.expired)
            .toList()
          ..sort(_byNextKeyTime);
    expiredCards =
        active
            .where((c) => freshness.evaluate(c, now) == Freshness.expired)
            .toList()
          ..sort(
            (a, b) => (b.effectiveExpiry ?? b.updatedAt).compareTo(
              a.effectiveExpiry ?? a.updatedAt,
            ),
          );
    doneCards = await cards.listByStatus({
      CardStatus.completed,
      CardStatus.archived,
    });
    notifyListeners();
    unawaited(_publishNativeSurfaces(now));
  }

  Future<void> _publishNativeSurfaces(DateTime now) async {
    await _publishFormCards(now);
    final card = activeCards.firstOrNull;
    final next = card?.nextKeyTime(now);
    try {
      await reminderGateway.syncLiveActivity(
        card == null || next == null
            ? null
            : LiveActivitySnapshot(
                cardId: card.id,
                title: displayTitle(card),
                timeLabel: _formTimeLabel(card, now),
                endsAt: next.$2,
              ),
      );
    } on AppFailure catch (failure) {
      AppLog.w('live_activity', '实况窗同步失败: ${failure.code.name}');
    }
  }

  Future<void> _publishFormCards(DateTime now) async {
    final snapshots = <FormCardSnapshot>[
      for (final card in activeCards.take(3))
        FormCardSnapshot(
          id: card.id,
          title: displayTitle(card),
          timeLabel: _formTimeLabel(card, now),
          urgent: freshness.evaluate(card, now) == Freshness.urgent,
        ),
    ];
    try {
      await formGateway.updateCards(snapshots);
    } on AppFailure catch (failure) {
      AppLog.w('forms', '服务卡片同步失败: ${failure.code.name}');
    } on Object catch (error) {
      AppLog.e('forms', '服务卡片同步异常', error);
    }
  }

  String _formTimeLabel(TemporalCard card, DateTime now) {
    final next = card.nextKeyTime(now);
    if (next == null) return '暂无关键时间';
    final time = next.$2;
    String two(int value) => value.toString().padLeft(2, '0');
    final timeLabel =
        '${next.$1.label} ${time.month}/${time.day} '
        '${two(time.hour)}:${two(time.minute)}';
    return card.secretValue == null
        ? timeLabel
        : '码 ${displaySecret(card.secretValue!)} · $timeLabel';
  }

  int _byNextKeyTime(TemporalCard a, TemporalCard b) {
    final now = clock.now();
    final an = a.nextKeyTime(now)?.$2;
    final bn = b.nextKeyTime(now)?.$2;
    if (an == null && bn == null) return b.updatedAt.compareTo(a.updatedAt);
    if (an == null) return 1;
    if (bn == null) return -1;
    return an.compareTo(bn);
  }

  void _onShared(SharedItem item) {
    unawaited(
      importFromBytes(
        item.bytes,
        source: ImportSource.share,
        displayName: item.displayName,
      ),
    );
  }

  void _onAction(ReminderActionEvent event) {
    unawaited(() async {
      try {
        if (event.action == ReminderActionType.route) {
          // 快捷方式/服务卡片等通用深链：只做路由，无卡片副作用。
          if (event.uri != null && event.uri!.isNotEmpty) {
            pendingRoute.value = event.uri;
          }
          return;
        }
        await cardService.handleAction(event);
        await refresh();
        if (event.action == ReminderActionType.opened ||
            event.action == ReminderActionType.viewSource) {
          pendingRoute.value = 'freshcue://card/${event.cardId}';
        }
      } on AppFailure catch (failure) {
        AppLog.w('reminder', '处理提醒动作失败: ${failure.code.name}');
      } on Object catch (error) {
        AppLog.e('reminder', '处理提醒动作异常', error);
      }
    }());
  }

  /// 导入流水线：复制 → OCR → 解析 → 草稿。
  Future<bool> importFromBytes(
    Uint8List bytes, {
    required ImportSource source,
    String? displayName,
  }) async {
    importFailure = null;
    pendingDraft = null;
    _setStage(ImportStage.reading);
    final now = clock.now();
    SourceAsset? asset;
    try {
      asset = await assetService.importBytes(
        bytes,
        source: source,
        now: now,
        displayName: displayName,
      );
      // SHA-256 去重：提示而非静默丢弃。
      String? dupCard;
      final existing = await assets.findBySha256(asset.sha256);
      if (existing != null) {
        final all = await cards.listByStatus(CardStatus.values.toSet());
        dupCard = all
            .where((c) => c.sourceAssetId == existing.id)
            .firstOrNull
            ?.id;
      }

      _setStage(ImportStage.recognizing);
      OcrResult? result;
      try {
        result = await ocr.recognizeImage(sandboxPath: asset.sandboxPath);
      } on AppFailure catch (f) {
        // OCR 失败降级：进入手动输入（空草稿），不中断建卡。
        AppLog.w('ocr', 'OCR失败: ${f.code.name}');
        importFailure = f;
      }

      _setStage(ImportStage.analyzing);
      final blocks = [
        if (result != null)
          for (final b in result.blocks)
            OcrBlock(
              id: IdGen.newId(),
              text: b.text,
              left: b.left,
              top: b.top,
              right: b.right,
              bottom: b.bottom,
              confidence: b.confidence,
              lineIndex: b.lineIndex,
            ),
      ];
      final drafts = _parser.parseCandidates(blocks: blocks, anchor: now);

      _setStage(ImportStage.preparing);
      pendingDraft = DraftContext(
        draft: drafts.first,
        additionalDrafts: drafts.skip(1).toList(growable: false),
        asset: asset,
        blocks: blocks,
        capturedAt: now,
        ocrProvider: result?.provider ?? OcrProvider.none,
        duplicateOfCardId: dupCard,
      );
      _setStage(ImportStage.done);
      return true;
    } on AppFailure catch (f) {
      if (asset != null) assetService.cleanup(asset);
      importFailure = f;
      _setStage(ImportStage.failed);
      return false;
    }
  }

  /// 手动文本降级：用户粘贴文字建卡。
  void importManualText(String text) {
    importFailure = null;
    final now = clock.now();
    final draft = _parser.parseText(text, now);
    pendingDraft = DraftContext(
      draft: draft,
      asset: null,
      blocks: const [],
      capturedAt: now,
      ocrProvider: OcrProvider.none,
    );
    importStage = ImportStage.done;
    notifyListeners();
  }

  void cancelImport() {
    final ctx = pendingDraft;
    if (ctx?.asset != null) assetService.cleanup(ctx!.asset!);
    pendingDraft = null;
    importFailure = null;
    importStage = ImportStage.idle;
    notifyListeners();
  }

  /// 确认草稿：写库后只启用用户选择的一种承载方式。
  Future<(String, DeliveryResult)> confirmDraft({
    required String title,
    required CardCategory category,
    String? location,
    String? secretValue,
    Map<TemporalRole, DateTime> anchors = const {},
    List<ReminderPlan>? customPlans,
    bool includePrimary = true,
    Set<int> additionalDraftIndexes = const {},
    String? notes,
    DeliveryMode? deliveryMode,
  }) async {
    final ctx = pendingDraft!;
    final now = clock.now();

    // 图片资产先落库（文件已写成功）；数据库失败清理文件。
    try {
      if (ctx.asset != null) await assets.save(ctx.asset!);
    } catch (e) {
      if (ctx.asset != null) assetService.cleanup(ctx.asset!);
      throw AppFailure(
        FailureCode.databaseWriteFailed,
        debugDetail: e.runtimeType.toString(),
      );
    }

    final selectedMode = deliveryMode ?? defaultDeliveryMode;

    Future<(String, DeliveryResult)> saveCard({
      required ParsedDraft draft,
      required String cardTitle,
      required CardCategory cardCategory,
      String? cardLocation,
      String? cardSecret,
      required Map<TemporalRole, DateTime> cardAnchors,
      List<ReminderPlan>? plansOverride,
      required DeliveryMode mode,
    }) async {
      final id = IdGen.newId();
      final card = TemporalCard(
        id: id,
        title: cardTitle,
        category: cardCategory,
        status: CardStatus.draft,
        sourceAssetId: ctx.asset?.id,
        rawOcrText: draft.cleanedText,
        location: cardLocation,
        secretValue: cardSecret,
        eventStartAt: cardAnchors[TemporalRole.eventStart],
        eventEndAt: cardAnchors[TemporalRole.eventEnd],
        deadlineAt: cardAnchors[TemporalRole.deadline],
        expiresAt: cardAnchors[TemporalRole.expiry],
        capturedAt: ctx.capturedAt,
        createdAt: now,
        updatedAt: now,
        overallConfidence: draft.confidenceScore,
        isSensitive:
            cardSecret != null || cardCategory == CardCategory.temporarySecret,
        notes: notes,
        deliveryMode: mode,
      );
      final plans =
          plansOverride ?? reminderPolicy.defaultPlans(card, IdGen.newId);
      DeliveryResult delivery;
      if (mode == DeliveryMode.appReminder && plans.isNotEmpty) {
        final granted = await reminderGateway.requestPermissionIfNeeded();
        if (!granted) {
          await cardService.confirmCard(card, plans, precomputedInstances: []);
          delivery = const DeliveryResult(
            mode: DeliveryMode.appReminder,
            permissionDenied: true,
          );
        } else {
          delivery = await cardService.confirmCard(card, plans);
        }
      } else {
        delivery = await cardService.confirmCard(card, plans);
      }
      if (ctx.blocks.isNotEmpty) {
        await ocrBlocks.saveAll(id, [
          for (final block in ctx.blocks)
            OcrBlock(
              id: IdGen.newId(),
              text: block.text,
              left: block.left,
              top: block.top,
              right: block.right,
              bottom: block.bottom,
              confidence: block.confidence,
              lineIndex: block.lineIndex,
            ),
        ]);
      }
      return (id, delivery);
    }

    String? cardId;
    var delivery = DeliveryResult(mode: selectedMode);
    if (includePrimary) {
      final saved = await saveCard(
        draft: ctx.draft,
        cardTitle: title,
        cardCategory: category,
        cardLocation: location,
        cardSecret: secretValue,
        cardAnchors: anchors,
        plansOverride: customPlans,
        mode: selectedMode,
      );
      cardId = saved.$1;
      delivery = saved.$2;
    }
    for (final index in additionalDraftIndexes.toList()..sort()) {
      if (index <= 0 || index >= ctx.drafts.length) continue;
      final draft = ctx.drafts[index];
      final saved = await saveCard(
        draft: draft,
        cardTitle: draft.title,
        cardCategory: draft.category,
        cardLocation: draft.location,
        cardSecret: draft.secretValue,
        cardAnchors: draft.suggestedAnchors,
        mode: selectedMode,
      );
      cardId ??= saved.$1;
      delivery = DeliveryResult(
        mode: selectedMode,
        failures: delivery.failures + saved.$2.failures,
        permissionDenied:
            delivery.permissionDenied || saved.$2.permissionDenied,
      );
    }
    if (cardId == null) {
      throw const AppFailure(
        FailureCode.unknown,
        debugDetail: 'no draft selected',
      );
    }

    pendingDraft = null;
    importStage = ImportStage.idle;
    await refresh();
    return (cardId, delivery);
  }

  Future<void> completeCard(String id) async {
    await cardService.complete(id);
    await refresh();
  }

  Future<void> archiveCard(String id) async {
    await cardService.archive(id);
    await refresh();
  }

  Future<void> restoreCard(String id) async {
    await cardService.restore(id);
    await refresh();
  }

  Future<void> deleteCard(String id) async {
    await cardService.deleteCard(id);
    await refresh();
  }

  Future<DeliveryResult> updateCardTimes(TemporalCard updated) async {
    final result = await cardService.rebuildDelivery(updated);
    await refresh();
    return result;
  }

  void _setStage(ImportStage s) {
    importStage = s;
    notifyListeners();
  }
}

/// 组装依赖（开发/测试：内存仓库 + Mock）。
/// Release 于 OHOS 设备上应改用 SQL 仓库（见 main.dart 与 native-integration 文档）。
AppController createMemoryAppController({
  Clock clock = const SystemClock(),
  required OcrGateway ocr,
  required ShareGateway share,
  required ReminderGateway reminderGateway,
  required CalendarGateway calendarGateway,
  required FormGateway formGateway,
  required String sandboxDir,
  bool usingMockPlatform = true,
  PlatformCapabilities capabilities = const PlatformCapabilities.unbridged(),
}) {
  final cards = MemoryCardRepository();
  final assets = MemoryAssetRepository();
  final blocks = MemoryOcrBlockRepository();
  final reminders = MemoryReminderRepository();
  final assetService = ImageAssetService(sandboxDir: sandboxDir);
  return AppController(
    cards: cards,
    assets: assets,
    ocrBlocks: blocks,
    reminders: reminders,
    settings: MemorySettingsRepository(),
    cardService: CardService(
      cards: cards,
      assets: assets,
      ocrBlocks: blocks,
      reminders: reminders,
      reminderGateway: reminderGateway,
      calendarGateway: calendarGateway,
      assetService: assetService,
      clock: clock,
    ),
    assetService: assetService,
    ocr: ocr,
    share: share,
    reminderGateway: reminderGateway,
    calendarGateway: calendarGateway,
    formGateway: formGateway,
    clock: clock,
    usingMockPlatform: usingMockPlatform,
    capabilities: capabilities,
  );
}

/// 组装依赖（OHOS 真机：SQL 仓库 + 真实 Channel 网关）。
AppController createSqlAppController({
  required Database db,
  Clock clock = const SystemClock(),
  required OcrGateway ocr,
  required ShareGateway share,
  required ReminderGateway reminderGateway,
  required CalendarGateway calendarGateway,
  required FormGateway formGateway,
  required String sandboxDir,
  bool usingMockPlatform = false,
  PlatformCapabilities capabilities = const PlatformCapabilities.unbridged(),
}) {
  final cards = SqlCardRepository(db);
  final assets = SqlAssetRepository(db);
  final blocks = SqlOcrBlockRepository(db);
  final reminders = SqlReminderRepository(db);
  final assetService = ImageAssetService(sandboxDir: sandboxDir);
  return AppController(
    cards: cards,
    assets: assets,
    ocrBlocks: blocks,
    reminders: reminders,
    settings: SqlSettingsRepository(db),
    cardService: CardService(
      cards: cards,
      assets: assets,
      ocrBlocks: blocks,
      reminders: reminders,
      reminderGateway: reminderGateway,
      calendarGateway: calendarGateway,
      assetService: assetService,
      clock: clock,
    ),
    assetService: assetService,
    ocr: ocr,
    share: share,
    reminderGateway: reminderGateway,
    calendarGateway: calendarGateway,
    formGateway: formGateway,
    clock: clock,
    usingMockPlatform: usingMockPlatform,
    capabilities: capabilities,
  );
}
