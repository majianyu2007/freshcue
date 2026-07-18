# 依赖审计

## 直接依赖（runtime）

| 包 | 版本 | 类型 | 用途 | OHOS 兼容 | 许可证 |
|---|---|---|---|---|---|
| flutter / flutter_localizations | SDK | — | 框架 + 中文本地化 | OHOS 分支同源 | BSD-3 |
| intl | 随 SDK | 纯 Dart | 本地化基础 | ✅ | BSD-3 |
| crypto | ^3.0.6 | 纯 Dart | SHA-256 去重 | ✅ | BSD-3 |
| sqflite_common | ^2.5.5 | 纯 Dart | SQLite API 层（无原生代码） | ✅（factory 由 ohos 插件注入） | BSD-2-Clause |
| path | ^1.9.0 | 纯 Dart | 路径拼接 | ✅ | BSD-3 |
| sqflite | git br_v2.4.2_ohos @1eefac74 | 平台插件 | OHOS 真机 SQLite/RDB 持久化 | ✅ 已编译进 HAP | BSD-2-Clause |

## dev 依赖

| 包 | 用途 | 许可证 |
|---|---|---|
| flutter_test | 测试 | BSD-3 |
| flutter_lints ^6.0.0 | 静态检查 | BSD-3 |
| sqflite_common_ffi ^2.3.6 | 桌面 SQLite 测试（不进产物） | BSD-2-Clause |

## git 依赖可复现性与署名（sqflite，§审计）

- **不可变提交锁定**：`pubspec.yaml` 用 `ref: 1eefac74916ee14cab6b58da4d60a84153bcb758`
  （完整 40 位 commit，非浮动 branch 名），`pubspec.lock` 记录同一
  `resolved-ref`。重新 `flutter pub get` 解析到同一 commit → **完全可复现**，
  不存在“把 branch 浮动引用误当可复现”的问题。
- **许可证**：CPF-Flutter/flutter_sqflite 沿用 Tekartik sqflite 的
  **BSD-2-Clause**（`LICENSE`：Copyright (c) 2019 Alexandre Roux Tekartik）。
  BSD-2-Clause 允许比赛/商业分发，要求保留版权声明与许可证文本。
- **署名**：分发物需在 NOTICE/关于页保留 sqflite 及 Flutter 引擎（BSD-3）版权。
  HAP 内 `flutter_assets/NOTICES.Z` 已含引擎依赖声明；建议应用“关于”页补 sqflite 署名。
- 更正记录：本表此前将三处 Tekartik 包标为 MIT，实为 BSD-2-Clause，已修正。

## 明确不引入

- 通用通知插件（flutter_local_notifications）：核心提醒必须走 Reminder Agent 桥接。
- image_picker / share 系列插件：无可靠 OHOS 实现，自建 ArkTS 桥接。
- 状态管理/路由/代码生成框架：项目规模不需要。

## 真机构建追加（dependency_overrides，锁 commit）

- ~~sqflite（openharmony-sig 适配分支）~~ **已正式采用**：CPF-Flutter/flutter_sqflite
  branch `br_v2.4.2_ohos` @ `1eefac74916ee14cab6b58da4d60a84153bcb758`，
  在 pubspec `dependencies` 中直接 git 引用（非 override），已随 HAP 编译。
  桌面测试仍用 `sqflite_common_ffi`（dev 依赖）。
