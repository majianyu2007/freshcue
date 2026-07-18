# Repository Guidelines

## Project Overview

FreshCue（截期）是面向 HarmonyOS NEXT 的 Flutter 应用：从截图导入短期信息，在设备端完成 OCR 和中文时间解析，经用户确认后生成时效卡片、代理提醒和服务卡片。无账号、无后端、无网络权限。

## Architecture & Data Flow

依赖方向必须向内：

```text
lib/core ← lib/domain ← lib/data ← lib/app + lib/features
                         ↑
                    lib/platform
```

主流程：`ShareGateway`/图库 → `ImageAssetService` → `OcrGateway` → `ScreenshotParser` → `ReviewPage` → `CardService` → repositories + `ReminderGateway` → `AppController` 刷新并发布 `FormGateway` 快照。

明确模式：

- `lib/domain/` 是纯 Dart；不得依赖 Flutter、数据库或平台 API。
- `CardService` 编排仓库和平台副作用；页面不得直接写 SQL。
- Gateway 隔离平台边界；MethodChannel 实现在 `channel_gateways.dart`，桌面 Mock 在 `mock_gateways.dart`。
- `AppController` 是单一 `ChangeNotifier`；项目不使用 Provider、Riverpod 或 Bloc。
- DI 为手工构造，入口在 `lib/app/composition.dart` 和 `lib/main.dart`。
- HarmonyOS ArkTS 插件在 `ohos/entry/src/main/ets/plugins/`；离线 OCR 原生模块在 `ohos/entry/src/main/cpp/`。

## Key Directories

- `lib/core/`：`Clock`、`Result`、`AppFailure`、日志脱敏、随机 ID。
- `lib/domain/entities/`：卡片、OCR、来源资产、提醒实体。
- `lib/domain/parser/`：时间片段定位、归一化、角色/分类/字段提取、聚合。
- `lib/domain/services/`：保鲜状态与提醒策略。
- `lib/data/`：SQLite schema/仓库、内存仓库、图片资产、`CardService`。
- `lib/platform/`：能力契约、Gateway、Channel/Mock 实现、注册表。
- `lib/app/`、`lib/features/`：组合、控制器、路由和页面。
- `ohos/entry/src/main/ets/`：Ability、分享/OCR/提醒/服务卡片桥接。
- `test/`：与 `lib/` 分层对应的测试。

## Development Commands

在仓库根运行：

```bash
flutter pub get
tool/check.sh
flutter analyze
flutter test
flutter test test/parser/parser_test.dart
flutter test --plain-name '演示样例完整解析'
flutter run
```

HAP 使用独立 OHOS Flutter 工具链：

```bash
hflutter build hap --debug
hflutter build hap --release
```

产物位于 `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`。包装命令在未配置签名时会返回非零，即使 `assembleHap` 已成功；检查输出和产物，不要把未签名描述为构建失败或可安装。ArkTS 变更必须用 HAP 构建验证。

## Code Conventions & Common Patterns

- Dart 文件用 `snake_case.dart`；类型 `UpperCamelCase`；成员 `lowerCamelCase`；私有成员 `_name`。
- 遵守 `analysis_options.yaml`：strict casts/inference/raw types、single quotes、trailing commas、ordered directives。
- 异步返回 `Future<T>`；异步回调里有意忽略 Future 时使用 `unawaited(...)`。
- 可恢复错误跨层使用 `AppFailure` + 稳定 `FailureCode`；Channel 的 `PlatformException.code` 统一映射，不向 UI 泄漏原始异常。
- 所有日志经 `AppLog`/`Redactor`；不得记录完整 OCR 文本、验证码或本机私有路径。
- 时间逻辑注入 `Clock`；领域代码不得直接调用 `DateTime.now()`。测试使用 `FixedClock`。
- nullable 字段的 `copyWith` 使用 sentinel 区分“未传入”和“显式置空”。
- DB migration 只追加，不修改已发布版本；当前 schema v2。
- 派生保鲜状态 `fresh/upcoming/urgent/expired` 不落库；持久状态仅 `draft/active/completed/archived`。
- 编辑时间必须取消旧平台提醒、重建实例并保持仓库一致；删除必须级联提醒、OCR 和沙箱资产。
- Release 禁止 Mock。是否使用 OHOS SQL 仅由运行平台和沙箱目录决定，不能依赖可能超时的 capability 握手。

## Important Files

- `lib/main.dart`：启动与持久化选择。
- `lib/app/composition.dart`：组合根及 Release/Mock 安全决策。
- `lib/app/app_controller.dart`：应用状态、导入、深链和服务卡片发布。
- `lib/domain/parser/screenshot_parser.dart`：解析管线入口。
- `lib/data/card_service.dart`：卡片/提醒生命周期编排。
- `lib/data/database/app_schema.dart`：SQLite schema 和 migrations。
- `lib/platform/gateways.dart`：平台契约。
- `lib/platform/platform_registry.dart`：Channel/Mock 注册。
- `ohos/entry/src/main/ets/entryability/EntryAbility.ets`：插件注册、Want 分发。
- `ohos/entry/src/main/ets/plugins/OcrPlugin.ets`：Core Vision → 离线 OCR fallback。
- `ohos/entry/src/main/ets/plugins/FormPlugin.ets`：服务卡片快照同步。
- `pubspec.yaml`、`analysis_options.yaml`、`tool/check.sh`：依赖与质量门。

## Runtime/Tooling Preferences

- 包管理：Dart pub；提交并尊重 `pubspec.lock`。
- 桌面开发/测试：系统 Homebrew Flutter 3.44.6。
- HAP 构建：`.toolchains/flutter-ohos/` 的 CPF-Flutter 3.35.8-ohos-1.0.1（通常由 `hflutter` 调用）。
- HarmonyOS：DevEco Studio 6.1.1 / API 24；打开 `ohos/` 子目录，不要对仓库根运行会覆盖原生工程的 scaffold 命令。
- 两套 Flutter 切换后出现 shader/cache 错误时先 `flutter clean`；不要提交 `.toolchains/`、HAP、签名材料或构建目录。
- `sqflite` OHOS fork 固定到 `pubspec.yaml` 的不可变 commit；不要改成浮动 branch。

## Testing & QA

主测试框架为 `flutter_test`；SQLite 测试用 `sqflite_common_ffi` 真内存数据库。`tool/check.sh` 是提交前规范门。新增行为应在对应层测试可观察契约，避免测试源码文本或实现细节。

重点覆盖：

- 解析年份推断、跨年、闰年、历史截图、角色冲突和高风险字段。
- `ReminderPolicy` 的跳过过去时间、去重、安静时段和 snooze。
- schema migration、nullable OCR confidence、资产回滚与级联删除。
- Release 禁 Mock、OHOS 不降级内存、Channel 契约和 provider 状态。
- Widget 导入/确认、OCR 失败可手工恢复、深链、权限拒绝、服务卡片脱敏。

设备状态必须用精确词：`已自动测试`、`已编译`、`未签名`、`待设备验证`。没有真机证据时，不得声称 OCR、分享、提醒、SQLite 或服务卡片已在 HarmonyOS 运行。
