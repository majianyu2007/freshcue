import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'app/app_controller.dart';
import 'app/composition.dart';
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

  // 持久化后端只看运行平台 + 沙箱目录，不看 OCR/分享/提醒 capability 握手：
  // 握手超时/失败绝不能让 OHOS 静默降级内存仓库、丢用户数据。
  final choice = choosePersistence(
    operatingSystem: Platform.operatingSystem,
    sandboxDir: caps.filesDir,
  );

  final AppController controller;
  switch (choice) {
    case PersistenceChoice.ohosSql:
      // OHOS 运行期：sqflite-ohos 持久化 + 沙箱 files 目录。
      // DB 打开失败 → 阻塞错误，绝不降级内存（否则用户建卡后重启即丢）。
      final sqflite.Database db;
      try {
        db = await openAppDatabase(
          sqflite.databaseFactory,
          p.join(caps.filesDir!, 'db', 'freshcue.db'),
        );
      } on Object catch (e) {
        AppLog.e('bootstrap', 'OHOS SQL 初始化失败，进入阻塞错误页', e);
        runApp(const _StorageFailureApp('本地存储初始化失败，暂时无法使用。请重启应用。'));
        return;
      }
      controller = createSqlAppController(
        db: db,
        clock: clock,
        ocr: registry.ocr,
        share: registry.share,
        reminderGateway: registry.reminders,
        calendarGateway: registry.calendar,
        formGateway: registry.forms,
        sandboxDir: p.join(caps.filesDir!, 'assets'),
        usingMockPlatform: registry.usingMocks,
        capabilities: caps,
      );
    case PersistenceChoice.ohosBlockedNoSandbox:
      // OHOS 运行期但握手未提供沙箱目录：不静默用内存，直接阻塞报错。
      AppLog.e('bootstrap', 'OHOS 运行期缺少沙箱目录，无法初始化持久化存储');
      runApp(const _StorageFailureApp('无法定位应用存储目录，暂时无法使用。请重启应用。'));
      return;
    case PersistenceChoice.devMemory:
      // 非 OHOS（桌面开发/测试）：内存仓库。OHOS Release 恒走 SQL 分支。
      controller = createMemoryAppController(
        clock: clock,
        ocr: registry.ocr,
        share: registry.share,
        reminderGateway: registry.reminders,
        calendarGateway: registry.calendar,
        formGateway: registry.forms,
        sandboxDir: p.join(Directory.systemTemp.path, 'freshcue_sandbox'),
        usingMockPlatform: registry.usingMocks,
        capabilities: caps,
      );
  }
  await controller.start();

  runApp(FreshCueApp(controller: controller));
}

/// 存储不可用时的阻塞错误页——替代静默降级内存，避免用户在“会丢数据”的状态下建卡。
class _StorageFailureApp extends StatelessWidget {
  const _StorageFailureApp(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
