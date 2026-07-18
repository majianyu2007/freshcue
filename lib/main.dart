import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'app/app_controller.dart';
import 'app/freshcue_app.dart';
import 'core/clock/clock.dart';
import 'core/logging/app_log.dart';
import 'data/repositories/sql_repositories.dart';
import 'platform/platform_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const clock = SystemClock();
  final registry = await PlatformRegistry.create(clock);
  final caps = registry.capabilities;

  final AppController controller;
  if (caps.isOhos && caps.filesDir != null) {
    // OHOS 真机：sqflite-ohos 持久化 + 沙箱 files 目录。
    final db = await openAppDatabase(
      sqflite.databaseFactory,
      p.join(caps.filesDir!, 'db', 'freshcue.db'),
    );
    controller = createSqlAppController(
      db: db,
      clock: clock,
      ocr: registry.ocr,
      share: registry.share,
      reminderGateway: registry.reminders,
      liveView: registry.liveView,
      sandboxDir: p.join(caps.filesDir!, 'assets'),
      usingMockPlatform: registry.usingMocks,
    );
  } else {
    // 非 OHOS（桌面开发/测试）：内存仓库。Release 不应走到这里——
    // OHOS Release 一律 SQL；此分支仅存在于开发环境。
    if (kReleaseMode) {
      AppLog.e('bootstrap', 'Release 构建缺少 OHOS 桥接，数据将不持久化');
    }
    controller = createMemoryAppController(
      clock: clock,
      ocr: registry.ocr,
      share: registry.share,
      reminderGateway: registry.reminders,
      liveView: registry.liveView,
      sandboxDir: p.join(Directory.systemTemp.path, 'freshcue_sandbox'),
      usingMockPlatform: registry.usingMocks,
    );
  }
  await controller.start();

  runApp(FreshCueApp(controller: controller));
}
