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

## 4. 空白 HAP 闸门 ✅

- `flutter create --platforms ohos hello_ohos` 生成完整 ohos 工程（AppScope/entry/
  build-profile.json5/hvigor）。
- `flutter build hap --debug` 成功，产物 `entry-default-unsigned.hap` 89M。
- 结论：工具链闭环成立，OHOS Flutter 分支可构建 HAP。

## 5. FreshCue HAP 闸门 ✅

- 安全合并：现有手写 `ohos/` 参考实现移入 `ohos-reference/`；以 3.35.8-ohos-1.0.1
  生成的 scaffold 作为构建骨架；bundleName 统一 `com.freshcue.app`。
- pubspec `environment.sdk` 由 `^3.12.2` 放宽为 `^3.9.0`（代码只用 Dart 3.0
  的 records/patterns/sealed，兼容 3.9.2）。无功能降级。
- 数据库：接入 CPF-Flutter `flutter_sqflite`（branch br_v2.4.2_ohos @
  1eefac74916ee14cab6b58da4d60a84153bcb758），sqflite_ohos 随 GeneratedPluginRegistrant
  编入 HAP；main.dart bootstrap 依据 capability handshake 选择 SQL(OHOS) / 内存(桌面)。
- analyze 0 issues；测试 119 通过（OHOS Flutter 与官方 Flutter 双跑）。

### HAP 产物（未签名）

> 更新（对抗式审计，干净 worktree @ HEAD `11ba8de`）：以下为完整 64 位 SHA-256。
> Debug 与 Release 的 `assembleHap` 均成功产出 unsigned HAP；唯一未完成阶段是**签名**
> （`signingConfigs: []`，需 DevEco 华为账号自动生成）。制品解包审计见 `docs/artifact-audit.md`。

| 阶段 | 模式 | 大小 | 完整 SHA-256（unsigned） |
|---|---|---:|---|
| FreshCue 全能力 HAP | Debug | 99,814,481 B (95.2 MiB) | `1efcc18da35d3ae46b07539bb64ba743d4ee371f36ab1f9773682f6fff41f0eb` |
| FreshCue 全能力 HAP | Release | 23,704,015 B (22.6 MiB) | `7c70be29c4adc68e3b05cb7c1b7dbcd29625c0ec5daca63927370575566a4d9f` |

> 注：早期报告只给 Debug（~95M）并截断 SHA-16；未区分 Release。Release AOT 后仅 22.6 MiB
> （Debug 的 95 MiB 主要来自 JIT `kernel_blob.bin` 47.5 MB + 未 strip 引擎）。SHA 随 Dart
> 代码变动而变，上表对应 HEAD `11ba8de`。

### SDK / API 兼容矩阵（§8，本机 API 24 d.ts 为证）

| 能力 | 使用 API | since（本机 d.ts） | 版本体系 | 影响 compatibleSdkVersion? |
|---|---|---:|---|---|
| OCR | `textRecognition.recognizeText` | @since 4 | HMS Core | 否（远低于 24） |
| 分享接收 | `systemShare.getSharedData` / `SharedData` | @since 4 | HMS Core | 否 |
| 代理提醒 | `reminderAgentManager.publishReminder` / `ReminderRequestCalendar` | @since 9 | OpenHarmony API | 否 |
| 图库 | `photoAccessHelper.PhotoViewPicker` | @since 12 | OpenHarmony API | **本项目 OHOS-API 使用上限** |

结论：本项目**自身**直接使用的 OHOS API 上限为 PhotoViewPicker `@since 12`；HMS OCR/分享用
HMS-since 4；提醒 `@since 9`。当前 `compatibleSdkVersion=6.1.1(24)` **高于**这些用量，是因为
(1) 本机仅装 API 24 SDK、(2) 曾为避免 DevEco 下载 API18 而上调、(3) OHOS Flutter 引擎 HAR 的
最低要求未独立枚举。**没有真机 + 更低 SDK 无法验证降低后是否仍可安装/运行**，故本阶段
**不盲目下调**（§8 明确禁止“为兼容更多设备虚假降版导致运行时缺 API”）。下调为后续
“有设备 + 多 SDK”验证项。

构建命令（完整环境变量）：
```bash
export HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH=$TOOL_HOME/tools/ohpm/bin:$TOOL_HOME/tools/hvigor/bin:$TOOL_HOME/tools/node/bin:$PATH
.toolchains/flutter-ohos/bin/flutter build hap --debug
# 产物: ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 6. 能力拉通记录

统一握手通道 `freshcue/capabilities`（ping / getCapabilities）已编译，诊断页显示
真实 compiled/available/reason。各 Kit 按 OCR→Share→Reminder 顺序**逐个编译验证**
（每次单独 clean build，且用注入类型错误的方式验证 ArkTS 类型检查真实生效）。

| 能力 | 真实 API（本机 HarmonyOS SDK API 24） | 状态 | 关键诚实说明 |
|---|---|---|---|
| Capability handshake | 自建 MethodChannel | 已编译 | — |
| 数据库 | sqflite_ohos（RDB） | 已编译 | schema v2 迁移冒烟测试通过 |
| OCR | `@hms.ai.ocr.textRecognition` recognizeText(Promise) | 已编译 | 结果用 cornerPoints 多边形→包围盒归一化；**无逐行 confidence，返回 null 不伪造** |
| 分享接收 | `PhotoViewPicker`（图库）+ `systemShare.getSharedData(want)`（Want/sendData skill 接收） | 已编译 | 这是 Want/Ability 级接收，非 ShareKit 发送 API；文档如实命名 |
| 代理提醒 | `@ohos.reminderAgentManager` publishReminder(Calendar) | 已编译 | **ActionButtonType 仅 CLOSE/SNOOZE，无自定义按钮**；“完成/延后”改为点击通知→进卡片在应用内操作，未硬编不存在字段 |
| 实况窗 | LiveViewKit | 参考代码 | feature flag 关闭，编译隔离在 ohos-reference/，不阻塞 HAP |
| Form Kit | — | 未开始 | 本阶段禁止 |

### 关键决策
- **SDK 品类更正**：DevEco 内置 **HarmonyOS 6.1.1 SDK（API 24）** 含全部 HMS Kit
  （Core Vision/Share/LiveView/Notification），无需另装。早前可行性报告基于独立
  OpenHarmony SDK API 23（无 HMS Kit）的判断已被本阶段更新。
- **INTERNET 权限**：scaffold 模板默认注入 `ohos.permission.INTERNET`，已删除
  （应用无任何网络代码，符合隐私 §19.2）。
- 参考实现（旧 ArkTS）与真实 SDK 的差异已在拉通中修正：`ActionButtonType.CUSTOM`
  不存在、OCR 用 cornerPoints 而非 itemRect、confidence 不存在等。

## 7. 未真机验证（外部阻塞）
无设备/模拟器（`hdc list targets` 为空）。全部运行期行为（OCR 真识别、分享冷/热启动、
提醒进程终止后触发、通知点击路由）仍标注未验证，见 docs/device-test-checklist.md。

