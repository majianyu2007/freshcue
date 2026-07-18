# FreshCue 可行性勘察报告（Phase 0）

> ⚠️ 历史文档（Phase 0 快照）。**已被后续进展取代**：现已固定 OHOS Flutter
> 3.35.8-ohos-1.0.1 + DevEco 内置 HarmonyOS 6.1.1 / **API 24** SDK，Debug 与 Release
> HAP 均**编译 + 打包通过**（未签名）。本文下方“本机不能完成 HAP 构建”“不声称 HAP
> 构建成功”等结论**已过时**，最新状态见 `docs/hap-bringup-report.md`、
> `docs/artifact-audit.md`、`docs/adversarial-audit.md`。以下保留原始 Phase 0 记录。

日期：2026-07-18 ｜ 勘察机器：macOS (Darwin 27.0.0, arm64)

## 1. 环境事实

| 项目 | 状态 | 详情 |
|---|---|---|
| Flutter SDK | ⚠️ 官方 stable，非 OHOS 分支 | 3.44.6 stable @ /opt/homebrew/bin/flutter，Dart 3.12.2 |
| OHOS Flutter 分支 | ❌ 未安装 | 本机不存在 `flutter build hap` 能力，无 `ohos` 平台模板 |
| DevEco Studio | ✅ 已安装 | /Applications/DevEco-Studio.app，自带 hvigor、node、ohpm |
| OpenHarmony SDK | ✅ API 23（6.1.0.31 Release） | ~/Library/OpenHarmony/Sdk/23（ets/js/native/toolchains/previewer） |
| hdc | ✅ 存在 | ~/Library/OpenHarmony/Sdk/23/toolchains/hdc |
| 真机/模拟器 | ❌ 无连接 | `hdc list targets` 为空 |
| JDK | ✅ | /usr/bin/java |
| Git | ✅ 空仓库 | main 分支，无提交，无用户未提交代码需要保护 |

## 2. 能力分级

### 已验证能力（本机实际运行过）
- Flutter stable 的 `create` / `pub get` / `analyze` / `test`（纯 Dart 与 widget 测试与 OHOS 分支同源，可迁移）。
- OpenHarmony SDK API 23 工具链文件存在（hvigorw、hdc、ets 组件）。

### 仅从文档确认、尚未运行的能力
- **Core Vision 文字识别**（`@kit.CoreVisionKit` / `textRecognition`）：API 文档确认存在于 HarmonyOS NEXT；本 OpenHarmony SDK 中的可用性需真机验证。
- **代理提醒**（`@ohos.reminderAgentManager`，需 `ohos.permission.PUBLISH_AGENT_REMINDER`）。
- **Share Kit 接收分享**（UIAbility `onCreate/onNewWant` + `wantConstant`）。
- **实况窗 Live View Kit**：需要测试/正式权益，本项目仅做前台实验能力 + feature flag。
- **Form Kit 服务卡片**：P1，与 Flutter 容器集成风险中等。
- `flutter build hap`：仅存在于 openharmony-sig/flutter_flutter 分支（3.7.12-ohos 起，较新分支跟进 3.22+）。

### 被环境阻塞的能力
- HAP 构建（缺 OHOS Flutter SDK 分支）——**本仓库不声称 HAP 构建成功**。
- 所有真机测试项（无设备）——见 docs/device-test-checklist.md，全部标注“未真机验证”。

## 3. 插件风险

| 依赖 | 类型 | OHOS 风险 | 决策 |
|---|---|---|---|
| crypto / path / intl | 纯 Dart | 无 | 采用 |
| sqflite_common | 纯 Dart（API 层） | 无 | 采用；真机侧由 openharmony-sig 适配 sqflite 插件提供 factory |
| sqflite（原生插件） | 平台插件 | 需使用 gitee openharmony-sig/flutter_packages 中的 ohos 分支，锁定 commit | 通过 `DatabaseDriver` 抽象隔离，缺席时用内存驱动（仅 Debug） |
| 图片选择/通知类通用插件 | 平台插件 | 大多无 OHOS 实现 | 不采用；一律走自建 ArkTS 桥接 channel |

## 4. 采用的 SDK/API 版本
- 目标：HarmonyOS NEXT / OpenHarmony API 23（compileSdk 以 DevEco 模板为准）。
- Dart/Flutter 代码兼容 Dart 3.x；避免使用 OHOS 分支尚未跟进的最新 Flutter API。

## 5. HAP 构建命令（环境就绪后）
```bash
# 1) 获取 OHOS Flutter SDK
git clone https://gitee.com/openharmony-sig/flutter_flutter.git ~/ohos-flutter
export PATH=~/ohos-flutter/bin:$PATH
# 2) 配置环境变量（示例，路径按本机调整，勿提交）
export TOOL_HOME=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$TOOL_HOME/sdk
export PATH=$TOOL_HOME/tools/ohpm/bin:$TOOL_HOME/tools/hvigor/bin:$PATH
# 3) 构建
flutter config --enable-ohos
flutter pub get
flutter build hap --debug    # 或 --release（需签名配置）
```

## 6. 真机验证清单
见 `docs/device-test-checklist.md`。当前全部未验证。

## 7. 结论与策略
本机**可以**完成：全部纯 Dart 领域层、时间解析引擎、数据库层（sqflite_common_ffi 桌面验证）、Flutter UI、Mock 平台适配器、全部自动化测试。
本机**不能**完成：HAP 构建、真机 OCR/提醒/分享/实况窗验证。
策略：平台能力全部隔离在 `lib/platform/` 接口后；`ohos/` 目录提供 ArkTS 参考实现（标注未真机验证）；文档提供精确的环境安装与接线说明。
