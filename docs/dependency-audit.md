# 依赖审计

## 直接依赖（runtime）

| 包 | 版本 | 类型 | 用途 | OHOS 兼容 | 许可证 |
|---|---|---|---|---|---|
| flutter / flutter_localizations | SDK | — | 框架 + 中文本地化 | OHOS 分支同源 | BSD-3 |
| intl | 随 SDK | 纯 Dart | 本地化基础 | ✅ | BSD-3 |
| crypto | ^3.0.6 | 纯 Dart | SHA-256 去重 | ✅ | BSD-3 |
| sqflite_common | ^2.5.5 | 纯 Dart | SQLite API 层（无原生代码） | ✅（factory 由 ohos 插件注入） | MIT |
| path | ^1.9.0 | 纯 Dart | 路径拼接 | ✅ | BSD-3 |

## dev 依赖

| 包 | 用途 | 许可证 |
|---|---|---|
| flutter_test | 测试 | BSD-3 |
| flutter_lints ^6.0.0 | 静态检查 | BSD-3 |
| sqflite_common_ffi ^2.3.6 | 桌面 SQLite 测试（不进产物） | MIT |

## 明确不引入

- 通用通知插件（flutter_local_notifications）：核心提醒必须走 Reminder Agent 桥接。
- image_picker / share 系列插件：无可靠 OHOS 实现，自建 ArkTS 桥接。
- 状态管理/路由/代码生成框架：项目规模不需要。

## 真机构建追加（dependency_overrides，锁 commit）

- sqflite（openharmony-sig/flutter_packages 适配分支）——接入时验证并记录 commit。
