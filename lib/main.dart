import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app/app_controller.dart';
import 'app/freshcue_app.dart';
import 'core/clock/clock.dart';
import 'platform/platform_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const clock = SystemClock();
  final registry = await PlatformRegistry.create(clock);

  // 沙箱目录：OHOS 真机应替换为 app 沙箱 files 路径（由桥接层提供）；
  // 开发环境使用系统临时目录。
  final sandboxDir = p.join(Directory.systemTemp.path, 'freshcue_sandbox');

  // 当前构建使用内存仓库（开发/演示）。OHOS 真机集成 sqflite-ohos 后
  // 切换为 SQL 仓库，见 docs/native-integration.md。
  final controller = createMemoryAppController(
    clock: clock,
    ocr: registry.ocr,
    share: registry.share,
    reminderGateway: registry.reminders,
    liveView: registry.liveView,
    sandboxDir: sandboxDir,
    usingMockPlatform: registry.usingMocks,
  );
  await controller.start();

  runApp(FreshCueApp(controller: controller));
}
