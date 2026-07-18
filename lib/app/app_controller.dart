import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart' show Database;

import '../core/clock/clock.dart';
import '../core/errors/app_failure.dart';
import '../core/logging/app_log.dart';
import '../core/utils/id_gen.dart';
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
import '../platform/gateways.dart';
import '../platform/mock_gateways.dart';

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
    this.duplicateOfCardId,
  });

  ParsedDraft draft;
  final SourceAsset? asset;
  final List<OcrBlock> blocks;
  final DateTime capturedAt;

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
    required this.liveView,
    required this.clock,
    required this.usingMockPlatform,
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
  final LiveViewGateway liveView;
  final Clock clock;
  final bool usingMockPlatform;

  late final ScreenshotParser _parser;
  final FreshnessPolicy freshness = const FreshnessPolicy();
  final ReminderPolicy reminderPolicy = const ReminderPolicy();

  List<TemporalCard> activeCards = [];
  List<TemporalCard> expiredCards = [];
  List<TemporalCard> doneCards = [];

  ImportStage importStage = ImportStage.idle;
  AppFailure? importFailure;
  DraftContext? pendingDraft;

  StreamSubscription<SharedItem>? _shareSub;
  StreamSubscription<ReminderActionEvent>? _actionSub;

  /// 深链/通知点击的待跳转卡片。
  final ValueNotifier<String?> pendingRoute = ValueNotifier(null);

  Future<void> start() async {
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

  void _onAction(ReminderActionEvent e) {
    unawaited(() async {
      await cardService.handleAction(e);
      await refresh();
      if (e.action == ReminderActionType.opened ||
          e.action == ReminderActionType.viewSource) {
        pendingRoute.value = 'freshcue://card/${e.cardId}';
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
      final draft = _parser.parse(blocks: blocks, anchor: now);

      _setStage(ImportStage.preparing);
      pendingDraft = DraftContext(
        draft: draft,
        asset: asset,
        blocks: blocks,
        capturedAt: now,
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

  /// 演示导入：使用 Mock OCR 样例文本（诊断页/空态入口，UI 标注演示）。
  Future<bool> importDemo() => importFromBytes(
    tinyPngBytes(),
    source: ImportSource.demo,
    displayName: '演示样例.png',
  );

  /// 手动文本降级：用户粘贴文字建卡。
  void importManualText(String text) {
    final now = clock.now();
    final draft = _parser.parseText(text, now);
    pendingDraft = DraftContext(
      draft: draft,
      asset: null,
      blocks: const [],
      capturedAt: now,
    );
    importStage = ImportStage.done;
    notifyListeners();
  }

  void cancelImport() {
    final ctx = pendingDraft;
    if (ctx?.asset != null) assetService.cleanup(ctx!.asset!);
    pendingDraft = null;
    importStage = ImportStage.idle;
    notifyListeners();
  }

  /// 确认草稿：写库 + 调度提醒。返回 (cardId, 调度失败数)。
  Future<(String, int)> confirmDraft({
    required String title,
    required CardCategory category,
    String? location,
    String? secretValue,
    Map<TemporalRole, DateTime> anchors = const {},
    List<ReminderPlan>? customPlans,
    String? notes,
  }) async {
    final ctx = pendingDraft!;
    final now = clock.now();
    final cardId = IdGen.newId();

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

    final card = TemporalCard(
      id: cardId,
      title: title,
      category: category,
      status: CardStatus.draft,
      sourceAssetId: ctx.asset?.id,
      rawOcrText: ctx.draft.cleanedText,
      location: location,
      secretValue: secretValue,
      eventStartAt: anchors[TemporalRole.eventStart],
      eventEndAt: anchors[TemporalRole.eventEnd],
      deadlineAt: anchors[TemporalRole.deadline],
      expiresAt: anchors[TemporalRole.expiry],
      capturedAt: ctx.capturedAt,
      createdAt: now,
      updatedAt: now,
      overallConfidence: ctx.draft.confidenceScore,
      isSensitive:
          secretValue != null || category == CardCategory.temporarySecret,
      notes: notes,
    );

    // 首次真正创建提醒时请求权限。
    final plans = customPlans ?? reminderPolicy.defaultPlans(card, IdGen.newId);
    var failures = 0;
    if (plans.isNotEmpty) {
      final granted = await reminderGateway.requestPermissionIfNeeded();
      if (!granted) {
        await cardService.confirmCard(card, plans, precomputedInstances: []);
        failures = -1; // 约定：-1 表示权限被拒（卡片已保存，提醒未启用）
      } else {
        failures = await cardService.confirmCard(card, plans);
      }
    } else {
      failures = await cardService.confirmCard(card, plans);
    }

    if (ctx.blocks.isNotEmpty) {
      await ocrBlocks.saveAll(cardId, ctx.blocks);
    }
    pendingDraft = null;
    importStage = ImportStage.idle;
    await refresh();
    return (cardId, failures);
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

  Future<int> updateCardTimes(TemporalCard updated) async {
    final failures = await cardService.rebuildReminders(updated);
    await refresh();
    return failures;
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
  required LiveViewGateway liveView,
  required String sandboxDir,
  bool usingMockPlatform = true,
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
      assetService: assetService,
      clock: clock,
    ),
    assetService: assetService,
    ocr: ocr,
    share: share,
    reminderGateway: reminderGateway,
    liveView: liveView,
    clock: clock,
    usingMockPlatform: usingMockPlatform,
  );
}

/// 组装依赖（OHOS 真机：SQL 仓库 + 真实 Channel 网关）。
AppController createSqlAppController({
  required Database db,
  Clock clock = const SystemClock(),
  required OcrGateway ocr,
  required ShareGateway share,
  required ReminderGateway reminderGateway,
  required LiveViewGateway liveView,
  required String sandboxDir,
  bool usingMockPlatform = false,
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
      assetService: assetService,
      clock: clock,
    ),
    assetService: assetService,
    ocr: ocr,
    share: share,
    reminderGateway: reminderGateway,
    liveView: liveView,
    clock: clock,
    usingMockPlatform: usingMockPlatform,
  );
}
