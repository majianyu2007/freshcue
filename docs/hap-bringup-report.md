# OHOS HAP Bring-up 报告

- 阶段开始 commit：`61dc2df`（分支 `feat/ohos-hap-bringup`）
- 日期：2026-07-18 ｜ 机器：macOS arm64 (Darwin 27)

## 1. SDK 品类勘察（关键更正）

DevEco Studio 自带 **HarmonyOS 6.1.1 SDK（API 24, Release）**，路径
`/Applications/DevEco-Studio.app/Contents/sdk/default/`，包含：

- `hms/ets/kits`：`@kit.CoreVisionKit`、`@kit.ShareKit`、`@kit.LiveViewKit`、
  `@kit.NotificationKit`、`@kit.BackgroundTasksKit` 等 51 个 HMS Kit ✅
- `openharmony/ets/api`：`@ohos.reminderAgentManager` ✅

另有独立 OpenHarmony SDK API 23（~/Library/OpenHarmony/Sdk/23，无 HMS Kit）。
**结论：厂商 Kit 在本机真实存在，走 DevEco 内置 HarmonyOS SDK。**

工具：hvigor/ohpm/node 18.20.1（DevEco 内置）、JDK 21（openjdk 21.0.11）、
hdc（两套 SDK 的 toolchains 均有）。设备：`hdc list targets` 为空（无设备）。

## 2. OHOS Flutter SDK 候选矩阵

（来源：`git ls-remote` https://gitcode.com/CPF-Flutter/flutter_flutter，2026-07-18）

| 候选 | 发布性质 | Dart 版本 | 预编译 Engine | 备注 | 结果 |
|---|---|---|---|---|---|
| 3.41.10-ohos-0.0.3-beta | beta，系列仅到 0.0.x | ~3.11+ | 待验证 | 过早期，工具链风险高 | 备选 |
| **3.35.8-ohos-1.0.1** | **正式 release**（另有 1.0.3/1.0.4-beta） | ~3.9.x | 随 tag 发布 | 最新的非 beta 系列 | **选定** |
| 3.35.8-ohos-1.0.4-beta | beta | ~3.9.x | — | 若 1.0.1 工具链有 bug 时回退 | 备选 |
| 3.27.5-ohos-1.0.6 | release，较旧 | ~3.6.x | 成熟 | 兜底 | 兜底 |

选择理由：release 优先于 beta；3.41 系列尚无 1.x release；3.35.8-ohos-1.0.1
是最新正式发布。实际可用性以 `flutter doctor`、空白 HAP 构建为准（见 §4）。

已知影响：pubspec `environment.sdk ^3.12.2` 需放宽至兼容 Dart 3.9
（代码使用的 records/patterns/sealed 均为 Dart 3.0 特性，预计兼容）。

安装位置：`.toolchains/flutter-ohos`（已 gitignore，不入库；
官方 Flutter 3.44.6 不受影响）。

## 3. 环境变量（本机，不含私密 token）

```bash
export FRESHCUE_OHOS_FLUTTER=$PWD/.toolchains/flutter-ohos/bin/flutter
export TOOL_HOME=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$TOOL_HOME/sdk
export PATH=$TOOL_HOME/tools/ohpm/bin:$TOOL_HOME/tools/hvigor/bin:$TOOL_HOME/tools/node/bin:$PATH
```

## 4. 空白 HAP 闸门

（进行中）

## 5. FreshCue Mock HAP 闸门

（待空白 HAP 通过）

## 6. 能力拉通记录

（待续）
