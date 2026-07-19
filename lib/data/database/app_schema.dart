import 'package:sqflite_common/sqlite_api.dart';

/// schema 版本与迁移。所有迁移从 v1 开始追加，禁止修改历史迁移。
class AppSchema {
  AppSchema._();

  static const int version = 3;

  static Future<void> onCreate(Database db, int version) async {
    for (var v = 1; v <= version; v++) {
      await _migrations[v]!(db);
    }
  }

  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    for (var v = oldV + 1; v <= newV; v++) {
      await _migrations[v]!(db);
    }
  }

  static final Map<int, Future<void> Function(Database)> _migrations = {
    1: (db) async {
      await db.execute('''
        CREATE TABLE temporal_cards (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          status TEXT NOT NULL,
          source_asset_id TEXT,
          raw_ocr_text TEXT,
          summary TEXT,
          location TEXT,
          secret_value TEXT,
          event_start_at INTEGER,
          event_end_at INTEGER,
          deadline_at INTEGER,
          expires_at INTEGER,
          captured_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          confirmed_at INTEGER,
          overall_confidence REAL NOT NULL DEFAULT 1.0,
          is_sensitive INTEGER NOT NULL DEFAULT 0,
          notes TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_cards_status ON temporal_cards(status)',
      );
      await db.execute(
        'CREATE INDEX idx_cards_deadline ON temporal_cards(deadline_at)',
      );
      await db.execute(
        'CREATE INDEX idx_cards_start ON temporal_cards(event_start_at)',
      );
      await db.execute('''
        CREATE TABLE source_assets (
          id TEXT PRIMARY KEY,
          original_display_name TEXT,
          sandbox_path TEXT NOT NULL,
          thumbnail_path TEXT,
          mime_type TEXT NOT NULL,
          width INTEGER NOT NULL DEFAULT 0,
          height INTEGER NOT NULL DEFAULT 0,
          size_bytes INTEGER NOT NULL DEFAULT 0,
          sha256 TEXT NOT NULL,
          import_source TEXT NOT NULL,
          imported_at INTEGER NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_assets_sha ON source_assets(sha256)');
      await db.execute('''
        CREATE TABLE ocr_blocks (
          id TEXT PRIMARY KEY,
          card_id TEXT NOT NULL,
          text TEXT NOT NULL,
          left REAL NOT NULL, top REAL NOT NULL,
          right REAL NOT NULL, bottom REAL NOT NULL,
          confidence REAL NOT NULL,
          line_index INTEGER NOT NULL,
          reading_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('CREATE INDEX idx_blocks_card ON ocr_blocks(card_id)');
      await db.execute('''
        CREATE TABLE temporal_candidates (
          id TEXT PRIMARY KEY,
          card_id TEXT NOT NULL,
          raw_text TEXT NOT NULL,
          normalized_at INTEGER,
          end_at INTEGER,
          role TEXT NOT NULL,
          role_confidence REAL NOT NULL,
          date_confidence REAL NOT NULL,
          explanation TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE reminder_plans (
          id TEXT PRIMARY KEY,
          card_id TEXT NOT NULL,
          anchor_role TEXT NOT NULL,
          offset_minutes INTEGER NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          sound INTEGER NOT NULL DEFAULT 1,
          vibration INTEGER NOT NULL DEFAULT 1,
          hide_on_lock_screen INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_plans_card ON reminder_plans(card_id)',
      );
      await db.execute('''
        CREATE TABLE reminder_instances (
          id TEXT PRIMARY KEY,
          card_id TEXT NOT NULL,
          plan_id TEXT NOT NULL,
          trigger_at INTEGER NOT NULL,
          platform_reminder_id INTEGER,
          status TEXT NOT NULL,
          failure_reason TEXT,
          snoozed_from TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_instances_card ON reminder_instances(card_id)',
      );
      await db.execute(
        'CREATE INDEX idx_instances_status ON reminder_instances(status, trigger_at)',
      );
      await db.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    },
    // v2：ocr_blocks.confidence 改为可空 —— Core Vision 等引擎不提供逐行置信度，
    // 存 null 比伪造数值更诚实。SQLite 无法直接改列约束，故重建表。
    2: (db) async {
      await db.execute('''
        CREATE TABLE ocr_blocks_v2 (
          id TEXT PRIMARY KEY,
          card_id TEXT NOT NULL,
          text TEXT NOT NULL,
          left REAL NOT NULL, top REAL NOT NULL,
          right REAL NOT NULL, bottom REAL NOT NULL,
          confidence REAL,
          line_index INTEGER NOT NULL,
          reading_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        INSERT INTO ocr_blocks_v2
        SELECT id, card_id, text, left, top, right, bottom,
               confidence, line_index, reading_order
        FROM ocr_blocks
      ''');
      await db.execute('DROP TABLE ocr_blocks');
      await db.execute('ALTER TABLE ocr_blocks_v2 RENAME TO ocr_blocks');
      await db.execute('CREATE INDEX idx_blocks_card ON ocr_blocks(card_id)');
    },
    // v3：记录卡片选择的提醒承载方式和系统日程 ID。
    // 旧卡片保持使用截期提醒，不改变既有行为。
    3: (db) async {
      await db.execute(
        "ALTER TABLE temporal_cards ADD COLUMN delivery_mode TEXT NOT NULL DEFAULT 'appReminder'",
      );
      await db.execute(
        'ALTER TABLE temporal_cards ADD COLUMN calendar_event_id INTEGER',
      );
    },
  };
}
