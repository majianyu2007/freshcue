# 对抗式验收审计（Release 前）

> 立场：把 bring-up 报告中的每条结论视为**待证声明**，主动找反例、复现失败、纠正夸大。
> 审计人：Claude Code（静态 / 编译 / 自动测试 / 制品解包，**无真机**）。
> 分支：`feat/ohos-hap-bringup` · HEAD `e5938d7` · 工作树干净。
> 结论词汇：`已静态证明` / `已编译证明` / `已自动测试` / `需设备验证` / `声明不成立，已修复` / `仍被阻塞`。

制品（干净 worktree @ HEAD `e5938d7`，OHOS Flutter 3.35.8-ohos-1.0.1 / API 24，均未签名）：

| 制品 | 大小 | 完整 SHA-256 |
|---|---:|---|
| Debug unsigned HAP | 99,814,537 B (95.2 MiB) | `4df3680651813ec0daecf68768784f1498a1dfb084cb765535848eac686e7163` |
| Release unsigned HAP | 23,704,015 B (22.6 MiB) | `2bee1dbd0d9f06e0eb63a90b50e69953c59d0f9f46459fec38e88c55e7f82563` |

> SHA 仅指纹本次（HEAD `e5938d7`）产物；HAP 归档含时间戳，逐次构建 SHA 会变，非可复现哈希。

制品逐项解包审计见 `docs/artifact-audit.md`。

---

## 1. 12 项已知问题处理

| # | 问题 | 证据 | 修复 | 验证命令 | 结果 |
|---|---|---|---|---|---|
| 1 | README 前文“Debug HAP 可构建”与“已知限制”中“HAP 未构建”冲突 | known-limitations 表首行曾写 `~~HAP 未构建~~` 但保留删除线歧义 | 统一为“Debug/Release 均编译+打包通过，仅签名被阻塞”，删除线彻底改写 | 见 README/known-limitations diff | 声明不成立，已修复 |
| 2 | README“诊断页真实 5 分钟提醒”——无设备时桌面只能 Mock | README §快速演示原文含“真实 5 分钟提醒” | 桌面演示章节改为“Mock 登记（不触发真实系统通知）” | `grep 真实 README.md` | 声明不成立，已修复 |
| 3 | README“任意 Flutter 3.4x stable”过度泛化 | 实测仅官方 3.44.6 + OHOS 3.35.8-ohos | 改为“已验证版本：官方 3.44.6（桌面测试）/ OHOS 3.35.8-ohos-1.0.1（HAP）” | README diff | 声明不成立，已修复 |
| 4 | README“Release 不声明网络权限”未经 Release 包审计 | 之前仅构建 Debug | 已构建 Release HAP 并解包合并 manifest，`requestPermissions` 仅 `PUBLISH_AGENT_REMINDER` | `grep ohos.permission release-unpack/module.json` | 已编译证明（Release 制品级） |
| 5 | “API 24 SDK 含全部 HMS Kit”表述过度 | 无法枚举“全部” | 改为“本机 SDK 含本项目实际使用 Kit（Core Vision / Share / Reminder / MediaLibrary）的声明与编译依赖” | d.ts 路径见 §8 | 声明不成立，已修复 |
| 6 | 仅给 SHA-256 前 16 位 | 旧报告截断 | 全文改用完整 64 位（见上表） | `shasum -a 256` | 已修复 |
| 7 | README“通知完成”暗示自定义完成按钮 | 本机 `ActionButtonType` 仅 CLOSE/SNOOZE | 改为“点击通知经 `freshcue://card/<id>` 深链进入卡片，在应用内完成/重排” | 见 §13 | 声明不成立，已修复 |
| 8 | 产品截图占位符长期挂着虚假完成感 | README 首行占位 | README 截图占位改为明确“待补桌面 Mock 演示截图（非真机）”，见 §15 说明 | README diff | 已修复（占位诚实化） |
| 9 | 报告未写明分支/是否合并 main/工作树状态 | — | 本文 §B 明确：`feat/ohos-hap-bringup`，未合并 main，工作树干净 | `git status --short` | 已修复 |
| 10 | main.dart 依 capability 选 SQL/内存，握手失败可能静默用内存丢数据 | `CapabilityService.fetch()` 遇 `PlatformException`/`MissingPluginException` 返回 `unbridged()` → `isOhos=false` → 内存分支 | 重构组合根：持久化改由 `Platform.operatingSystem=='ohos'` 决定；OHOS 缺沙箱/DB 失败→阻塞错误页，绝不静默内存。抽出 `choosePersistence`（纯函数）+ 单测 | `flutter test test/app/composition_test.dart` | 声明不成立，已修复 |
| 11 | 报告未给 compile/target/compatible SDK 与 ABI | — | 解包 manifest：compileSdkVersion `6.1.1.125`、compatible/target API 24、ABI `arm64-v8a`。见 §8 兼容性讨论 | `cat release-unpack/module.json` | 已编译证明 |
| 12 | Debug unsigned 不代表可提交 Release | 旧报告只到 Debug | Release HAP 已编译+打包通过（`assembleHap` 成功产出 unsigned），仅**签名**阶段被阻塞（需 DevEco 华为账号 GUI 登录） | 见 §C / §6 | 已编译证明（签名仍被阻塞） |

---

## 2. 声明—证据账本

| 声明 | 所需证据 | 当前证据 | 结论 |
|---|---|---|---|
| 空白 HAP 可构建 | 干净 scaffold assembleHap 成功 | 历史 bring-up 已产 Mock HAP（commit 3d3786f）；本轮直接验证 FreshCue 包 | 已编译证明 |
| FreshCue Debug HAP 可构建 | 干净 worktree 产 unsigned Debug HAP | 95.2 MiB unsigned HAP，SHA 见上 | 已编译证明（未签名） |
| FreshCue Release HAP 可构建 | 干净 worktree 产 unsigned Release HAP | 22.6 MiB unsigned HAP，manifest `buildMode:release`/`debug:false`/`apiReleaseType:Release` | 已编译证明（未签名，签名阻塞） |
| OcrPlugin 被编译 | 出现在 HAP 编译产物 | `strings release-unpack/ets/modules.abc` → `OcrPlugin`×5 | 已编译证明 |
| SharePlugin 被编译且被 EntryAbility 注册 | 字节码含类 + 注册链 | modules.abc `SharePlugin`×5；`EntryAbility.ets` `flutterEngine.getPlugins().add(this.sharePlugin)` | 已编译证明 |
| ReminderPlugin 被编译且被注册 | 同上 | modules.abc `ReminderPlugin`×5；EntryAbility `add(this.reminderPlugin)` | 已编译证明 |
| CapabilitiesPlugin 被注册并返回契约字段 | 注册链 + 契约 | EntryAbility `add(new CapabilitiesPlugin())`；channel `freshcue/capabilities` ping/getCapabilities；Dart 侧 `PlatformCapabilities.fromMap` 缺字段容错 | 已编译证明 + 已自动测试（capabilities_test） |
| OHOS 使用真实 SQL 而非内存 | 组合根按平台选 SQL | `choosePersistence(os:'ohos', dir≠null)→ohosSql`；main.dart OHOS 分支用 `sqflite.databaseFactory` | 已静态证明 + 已自动测试；持久化本身 需设备验证 |
| Release 禁止 Mock | 代码 + Release 配置测试 | `shouldUseMockGateways(isDebug:false)→false`（即使 forceMock=true）；registry 二重 assert | 已自动测试（composition_test 覆盖 Release 配置对象） |
| Release 最终权限无 INTERNET | 合并 manifest | release-unpack/module.json `requestPermissions` 仅 `PUBLISH_AGENT_REMINDER` | 已编译证明（制品级） |
| Share 冷/热启动只消费一次 | 去重逻辑 + 测试 | SharePlugin `consumedIds` 去重；Dart `consumeInitialShare(id)`；EntryAbility 冷启 `dispatchWant(getWant,true)` / 热启 `onNewWant→dispatchWant(want,false)` | 已静态证明；运行期 需设备验证 |
| Reminder 深链经 cardId 校验 | 路由安全失败 | `dispatchWant` 仅 `freshcue://card/` 前缀进 `emitOpened`；`handleAction(opened, 不存在 cardId)` 不抛异常 | 已自动测试（card_service_test 新增 2 项） |
| OCR confidence 缺失返回 null | 端到端可空 | `OcrResultBlock.confidence` 可空；schema v2 迁移；DB 测试 null 用例 | 已自动测试 |
| Live View 不在当前 HAP 编译路径 | 制品无该类 | modules.abc `LiveView`×0；源码在 `ohos-reference/`（编译隔离） | 已编译证明 |
| HAP 尚未设备运行验证 | 无 hdc 目标 | `hdc list targets` 空 | 仍被阻塞（需设备验证） |

---

## 3. 仓库真实性检查（§3）

- 分支：`feat/ohos-hap-bringup`，13 个提交领先 `main`（bring-up 12 + 本轮安全修复 1）。未自动合并 main。
- `git status --short`：干净。`git diff --check`：无空白/冲突标记。
- `git ls-files .toolchains`、`git ls-files '*.hap'`：均空 —— 工具链/HAP/签名材料未被跟踪。
- 秘密扫描：无 `*.p12/*.cer/*.pem/*.key`、无 token/证书被跟踪。
- 本机绝对路径：源码/构建脚本中**无** `/Users/…`；仅 `docs/native-integration.md` 为可读性写了本机示例路径 → 已改为 `<repo>` / `<DevEco>` 占位符。
- `tool/check.sh`：`-rwxr-xr-x`，可执行位正常，仓库根可运行。

## 4. 干净 worktree 复现（§5）

`git worktree add --detach /tmp/freshcue-audit-wt HEAD`（不含 `.dart_tool`/`build`/`.hvigor`/`.toolchains`/未跟踪文件；OHOS Flutter SDK 复用 `.toolchains`）。逐步 rc 见 §C。
关键发现：**干净 worktree 与当前目录结论一致** —— 无隐式依赖；Debug/Release 的 `assembleHap` 均成功产出 unsigned HAP，唯一“失败”是 flutter 包装器在末尾的**签名配置检查**（`signingConfigs: []`），非编译/打包失败。

## 5. 结论

- **建议合并 main**：可以（在用户确认后）。审计发现 1 项真实安全缺陷（§问题 10 数据库静默降级）已修复，其余为文档夸大，已纠正。
- **是否达到“可交给真机测试”**：是 —— HAP 编译+打包通过、权限/ABI/bundle 已审计、Release 无可启用 Mock、OHOS 不再静默用内存。剩余仅签名（需华为账号）与全部运行期行为需真机。
- 发现问题：12 项已知 + 2 项新增（数据库静默降级=真实缺陷；依赖许可证标注 MIT 实为 BSD-2-Clause）。修复：14 项全部处理。剩余阻塞：签名（外部账号）+ 全部运行期能力（无设备）。
