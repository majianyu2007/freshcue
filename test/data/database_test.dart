import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freshcue/data/database/app_schema.dart';
import 'package:freshcue/data/repositories/sql_repositories.dart';
import 'package:freshcue/domain/entities/reminder.dart';
import 'package:freshcue/domain/entities/source_asset.dart';
import 'package:freshcue/domain/entities/temporal_card.dart';
import 'package:freshcue/domain/enums/enums.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  final now = DateTime(2026, 7, 18, 10, 0);

  late Database db;

  setUp(() async {
    db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppSchema.version,
        onCreate: AppSchema.onCreate,
        onUpgrade: AppSchema.onUpgrade,
      ),
    );
  });

  tearDown(() => db.close());

  TemporalCard card(String id) => TemporalCard(
    id: id,
    title: '校园创新体验日',
    category: CardCategory.event,
    status: CardStatus.active,
    location: '大学生活动中心 201',
    secretValue: 'A7281',
    deadlineAt: DateTime(2026, 7, 20, 18, 0),
    eventStartAt: DateTime(2026, 7, 25, 14, 0),
    eventEndAt: DateTime(2026, 7, 25, 16, 30),
    isSensitive: true,
    createdAt: now,
    updatedAt: now,
  );

  test('新建数据库：schema 版本正确、全部表存在', () async {
    final tables = await db.query('sqlite_master', where: "type = 'table'");
    final names = tables.map((t) => t['name']).toSet();
    for (final t in [
      'temporal_cards',
      'source_assets',
      'ocr_blocks',
      'temporal_candidates',
      'reminder_plans',
      'reminder_instances',
      'app_settings',
    ]) {
      expect(names, contains(t), reason: '缺表 $t');
    }
    expect(await db.getVersion(), AppSchema.version);
  });

  test('创建完整卡片并读回全部字段', () async {
    final repo = SqlCardRepository(db);
    await repo.save(card('c1'));
    final loaded = (await repo.findById('c1'))!;
    expect(loaded.title, '校园创新体验日');
    expect(loaded.deadlineAt, DateTime(2026, 7, 20, 18, 0));
    expect(loaded.eventEndAt, DateTime(2026, 7, 25, 16, 30));
    expect(loaded.isSensitive, isTrue);
    expect(loaded.secretValue, 'A7281');
  });

  test('按状态查询', () async {
    final repo = SqlCardRepository(db);
    await repo.save(card('c1'));
    await repo.save(card('c2').copyWith(status: CardStatus.archived));
    final active = await repo.listByStatus({CardStatus.active});
    expect(active.map((c) => c.id), ['c1']);
  });

  test('资产按 sha256 去重查询', () async {
    final repo = SqlAssetRepository(db);
    await repo.save(
      SourceAsset(
        id: 'a1',
        sandboxPath: '/x/a1.png',
        mimeType: 'image/png',
        sha256: 'abc',
        importSource: ImportSource.share,
        importedAt: now,
      ),
    );
    expect((await repo.findBySha256('abc'))!.id, 'a1');
    expect(await repo.findBySha256('zzz'), isNull);
  });

  test('提醒计划与实例保存/替换', () async {
    final repo = SqlReminderRepository(db);
    await repo.savePlans('c1', [
      const ReminderPlan(
        id: 'p1',
        cardId: 'c1',
        anchorRole: TemporalRole.deadline,
        offsetMinutes: 120,
      ),
    ]);
    final plans = await repo.plansByCard('c1');
    expect(plans.single.describe(), '截止前 2 小时');

    await repo.replaceInstances('c1', [
      ReminderInstance(
        id: 'i1',
        cardId: 'c1',
        planId: 'p1',
        triggerAt: DateTime(2026, 7, 20, 16, 0),
        platformReminderId: 42,
        status: ReminderStatus.scheduled,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final scheduled = await repo.allScheduledInstances();
    expect(scheduled.single.platformReminderId, 42);
  });

  test('OCR block 保存与级联删除', () async {
    final repo = SqlOcrBlockRepository(db);
    await repo.saveAll('c1', [
      const OcrBlock(
        id: 'b1',
        text: '报名截止：7月20日 18:00',
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.25,
        confidence: 0.96,
        lineIndex: 1,
      ),
    ]);
    expect((await repo.listByCard('c1')).single.text, contains('报名截止'));
    await repo.deleteByCard('c1');
    expect(await repo.listByCard('c1'), isEmpty);
  });

  test('设置读写', () async {
    final repo = SqlSettingsRepository(db);
    expect(await repo.get('quiet_start'), isNull);
    await repo.set('quiet_start', '23');
    expect(await repo.get('quiet_start'), '23');
  });

  test('损坏/缺字段记录容错（可空字段为 null 不崩溃）', () async {
    await db.insert('temporal_cards', {
      'id': 'broken',
      'title': 't',
      'category': '不存在的分类',
      'status': '不存在的状态',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    final repo = SqlCardRepository(db);
    final c = (await repo.findById('broken'))!;
    expect(c.category, CardCategory.generic); // fromName 回退
    expect(c.status, CardStatus.draft);
  });

  test('文件数据库跨连接持久化（模拟应用重启）', () async {
    final path = '${Directory.systemTemp.createTempSync('freshcue').path}/t.db';
    final db1 = await openAppDatabase(factory, path);
    await SqlCardRepository(db1).save(card('c9'));
    await db1.close();
    final db2 = await openAppDatabase(factory, path);
    expect((await SqlCardRepository(db2).findById('c9'))!.title, '校园创新体验日');
    await db2.close();
  });
}
