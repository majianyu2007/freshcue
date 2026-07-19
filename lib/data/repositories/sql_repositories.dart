import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entities/reminder.dart';
import '../../domain/entities/source_asset.dart';
import '../../domain/entities/temporal_card.dart';
import '../../domain/enums/enums.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_schema.dart';

/// 打开数据库。[factory] 注入：测试用 sqflite_common_ffi，
/// OHOS 真机由 openharmony-sig sqflite 插件提供（见 docs/native-integration.md）。
Future<Database> openAppDatabase(DatabaseFactory factory, String path) =>
    factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppSchema.version,
        onCreate: AppSchema.onCreate,
        onUpgrade: AppSchema.onUpgrade,
      ),
    );

int? _ms(DateTime? t) => t?.millisecondsSinceEpoch;
DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

class SqlCardRepository implements CardRepository {
  SqlCardRepository(this._db);
  final Database _db;

  @override
  Future<List<TemporalCard>> listByStatus(Set<CardStatus> statuses) async {
    final rows = await _db.query(
      'temporal_cards',
      where: 'status IN (${List.filled(statuses.length, '?').join(',')})',
      whereArgs: statuses.map((s) => s.name).toList(),
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<TemporalCard?> findById(String id) async {
    final rows = await _db.query(
      'temporal_cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> save(TemporalCard c) => _db.insert('temporal_cards', {
    'id': c.id,
    'title': c.title,
    'category': c.category.name,
    'status': c.status.name,
    'source_asset_id': c.sourceAssetId,
    'raw_ocr_text': c.rawOcrText,
    'summary': c.summary,
    'location': c.location,
    'secret_value': c.secretValue,
    'event_start_at': _ms(c.eventStartAt),
    'event_end_at': _ms(c.eventEndAt),
    'deadline_at': _ms(c.deadlineAt),
    'expires_at': _ms(c.expiresAt),
    'captured_at': _ms(c.capturedAt),
    'created_at': c.createdAt.millisecondsSinceEpoch,
    'updated_at': c.updatedAt.millisecondsSinceEpoch,
    'confirmed_at': _ms(c.confirmedAt),
    'overall_confidence': c.overallConfidence,
    'is_sensitive': c.isSensitive ? 1 : 0,
    'notes': c.notes,
    'delivery_mode': c.deliveryMode.name,
    'calendar_event_id': c.calendarEventId,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> delete(String id) =>
      _db.delete('temporal_cards', where: 'id = ?', whereArgs: [id]);

  TemporalCard _fromRow(Map<String, Object?> r) => TemporalCard(
    id: r['id']! as String,
    title: r['title']! as String,
    category: CardCategory.fromName(r['category']! as String),
    status: CardStatus.fromName(r['status']! as String),
    sourceAssetId: r['source_asset_id'] as String?,
    rawOcrText: r['raw_ocr_text'] as String?,
    summary: r['summary'] as String?,
    location: r['location'] as String?,
    secretValue: r['secret_value'] as String?,
    eventStartAt: _dt(r['event_start_at']),
    eventEndAt: _dt(r['event_end_at']),
    deadlineAt: _dt(r['deadline_at']),
    expiresAt: _dt(r['expires_at']),
    capturedAt: _dt(r['captured_at']),
    createdAt: _dt(r['created_at'])!,
    updatedAt: _dt(r['updated_at'])!,
    confirmedAt: _dt(r['confirmed_at']),
    overallConfidence: (r['overall_confidence'] as num?)?.toDouble() ?? 1.0,
    isSensitive: (r['is_sensitive'] as int? ?? 0) == 1,
    notes: r['notes'] as String?,
    deliveryMode: DeliveryMode.fromName(
      r['delivery_mode'] as String? ?? DeliveryMode.appReminder.name,
    ),
    calendarEventId: r['calendar_event_id'] as int?,
  );
}

class SqlAssetRepository implements AssetRepository {
  SqlAssetRepository(this._db);
  final Database _db;

  @override
  Future<SourceAsset?> findById(String id) async {
    final rows = await _db.query(
      'source_assets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<SourceAsset?> findBySha256(String sha256) async {
    final rows = await _db.query(
      'source_assets',
      where: 'sha256 = ?',
      whereArgs: [sha256],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> save(SourceAsset a) => _db.insert('source_assets', {
    'id': a.id,
    'original_display_name': a.originalDisplayName,
    'sandbox_path': a.sandboxPath,
    'thumbnail_path': a.thumbnailPath,
    'mime_type': a.mimeType,
    'width': a.width,
    'height': a.height,
    'size_bytes': a.sizeBytes,
    'sha256': a.sha256,
    'import_source': a.importSource.name,
    'imported_at': a.importedAt.millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> delete(String id) =>
      _db.delete('source_assets', where: 'id = ?', whereArgs: [id]);

  SourceAsset _fromRow(Map<String, Object?> r) => SourceAsset(
    id: r['id']! as String,
    originalDisplayName: r['original_display_name'] as String?,
    sandboxPath: r['sandbox_path']! as String,
    thumbnailPath: r['thumbnail_path'] as String?,
    mimeType: r['mime_type']! as String,
    width: r['width'] as int? ?? 0,
    height: r['height'] as int? ?? 0,
    sizeBytes: r['size_bytes'] as int? ?? 0,
    sha256: r['sha256']! as String,
    importSource: ImportSource.values.firstWhere(
      (s) => s.name == r['import_source'],
      orElse: () => ImportSource.gallery,
    ),
    importedAt: _dt(r['imported_at'])!,
  );
}

class SqlOcrBlockRepository implements OcrBlockRepository {
  SqlOcrBlockRepository(this._db);
  final Database _db;

  @override
  Future<List<OcrBlock>> listByCard(String cardId) async {
    final rows = await _db.query(
      'ocr_blocks',
      where: 'card_id = ?',
      whereArgs: [cardId],
      orderBy: 'line_index',
    );
    return [
      for (final r in rows)
        OcrBlock(
          id: r['id']! as String,
          cardId: r['card_id'] as String?,
          text: r['text']! as String,
          left: (r['left']! as num).toDouble(),
          top: (r['top']! as num).toDouble(),
          right: (r['right']! as num).toDouble(),
          bottom: (r['bottom']! as num).toDouble(),
          confidence: (r['confidence'] as num?)?.toDouble(),
          lineIndex: r['line_index']! as int,
          readingOrder: r['reading_order'] as int? ?? 0,
        ),
    ];
  }

  @override
  Future<void> saveAll(String cardId, List<OcrBlock> blocks) => _db.transaction(
    (txn) async {
      await txn.delete('ocr_blocks', where: 'card_id = ?', whereArgs: [cardId]);
      for (final b in blocks) {
        await txn.insert('ocr_blocks', {
          'id': b.id,
          'card_id': cardId,
          'text': b.text,
          'left': b.left,
          'top': b.top,
          'right': b.right,
          'bottom': b.bottom,
          'confidence': b.confidence,
          'line_index': b.lineIndex,
          'reading_order': b.readingOrder,
        });
      }
    },
  );

  @override
  Future<void> deleteByCard(String cardId) =>
      _db.delete('ocr_blocks', where: 'card_id = ?', whereArgs: [cardId]);
}

class SqlReminderRepository implements ReminderRepository {
  SqlReminderRepository(this._db);
  final Database _db;

  @override
  Future<List<ReminderPlan>> plansByCard(String cardId) async {
    final rows = await _db.query(
      'reminder_plans',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    return [
      for (final r in rows)
        ReminderPlan(
          id: r['id']! as String,
          cardId: r['card_id']! as String,
          anchorRole: TemporalRole.fromName(r['anchor_role']! as String),
          offsetMinutes: r['offset_minutes']! as int,
          enabled: (r['enabled'] as int? ?? 1) == 1,
          sound: (r['sound'] as int? ?? 1) == 1,
          vibration: (r['vibration'] as int? ?? 1) == 1,
          hideOnLockScreen: (r['hide_on_lock_screen'] as int? ?? 0) == 1,
        ),
    ];
  }

  @override
  Future<List<ReminderInstance>> instancesByCard(String cardId) async {
    final rows = await _db.query(
      'reminder_instances',
      where: 'card_id = ?',
      whereArgs: [cardId],
      orderBy: 'trigger_at',
    );
    return rows.map(_instanceFromRow).toList();
  }

  @override
  Future<List<ReminderInstance>> allScheduledInstances() async {
    final rows = await _db.query(
      'reminder_instances',
      where: 'status = ?',
      whereArgs: [ReminderStatus.scheduled.name],
      orderBy: 'trigger_at',
    );
    return rows.map(_instanceFromRow).toList();
  }

  @override
  Future<void> savePlans(String cardId, List<ReminderPlan> plans) =>
      _db.transaction((txn) async {
        await txn.delete(
          'reminder_plans',
          where: 'card_id = ?',
          whereArgs: [cardId],
        );
        for (final p in plans) {
          await txn.insert('reminder_plans', {
            'id': p.id,
            'card_id': p.cardId,
            'anchor_role': p.anchorRole.name,
            'offset_minutes': p.offsetMinutes,
            'enabled': p.enabled ? 1 : 0,
            'sound': p.sound ? 1 : 0,
            'vibration': p.vibration ? 1 : 0,
            'hide_on_lock_screen': p.hideOnLockScreen ? 1 : 0,
          });
        }
      });

  @override
  Future<void> saveInstance(ReminderInstance i) => _db.insert(
    'reminder_instances',
    _instanceToRow(i),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> replaceInstances(
    String cardId,
    List<ReminderInstance> instances,
  ) => _db.transaction((txn) async {
    await txn.delete(
      'reminder_instances',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    for (final i in instances) {
      await txn.insert('reminder_instances', _instanceToRow(i));
    }
  });

  @override
  Future<void> deleteByCard(String cardId) => _db.transaction((txn) async {
    await txn.delete(
      'reminder_plans',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    await txn.delete(
      'reminder_instances',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
  });

  Map<String, Object?> _instanceToRow(ReminderInstance i) => {
    'id': i.id,
    'card_id': i.cardId,
    'plan_id': i.planId,
    'trigger_at': i.triggerAt.millisecondsSinceEpoch,
    'platform_reminder_id': i.platformReminderId,
    'status': i.status.name,
    'failure_reason': i.failureReason,
    'snoozed_from': i.snoozedFromInstanceId,
    'created_at': i.createdAt.millisecondsSinceEpoch,
    'updated_at': i.updatedAt.millisecondsSinceEpoch,
  };

  ReminderInstance _instanceFromRow(Map<String, Object?> r) => ReminderInstance(
    id: r['id']! as String,
    cardId: r['card_id']! as String,
    planId: r['plan_id']! as String,
    triggerAt: _dt(r['trigger_at'])!,
    platformReminderId: r['platform_reminder_id'] as int?,
    status: ReminderStatus.values.firstWhere(
      (s) => s.name == r['status'],
      orElse: () => ReminderStatus.failed,
    ),
    failureReason: r['failure_reason'] as String?,
    snoozedFromInstanceId: r['snoozed_from'] as String?,
    createdAt: _dt(r['created_at'])!,
    updatedAt: _dt(r['updated_at'])!,
  );
}

class SqlSettingsRepository implements SettingsRepository {
  SqlSettingsRepository(this._db);
  final Database _db;

  @override
  Future<String?> get(String key) async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> set(String key, String value) => _db.insert('app_settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
