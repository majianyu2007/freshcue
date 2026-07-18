# 截期 FreshCue

> 把截图中的临时信息转换成会提醒、会过期的时效卡片。
> *Turn screenshots into timely, expiring cards.*

（产品截图占位：首页 / 确认页 / 通知 —— **待补桌面 Mock 演示截图**，将明确标注“桌面 Mock 演示”，非 HarmonyOS 真机截图）

## 为什么

聊天里的活动通知、快递取件码、票务信息……以截图形式散落在相册里，
**时间一到就变成垃圾，但在此之前你必须记得它**。FreshCue 用端侧 OCR +
自研中文时间语义解析，把截图变成有生命周期的「时效卡片」：

1. **一图多时间**：区分「报名截止」「活动开始」「失效」「发布时间」等语义角色；
2. **完整生命周期**：创建 → 临近 → 提醒 → 完成/过期自动收纳；
3. **证据可回溯**：每个字段可定位回原截图 OCR 高亮框；
4. **提醒跟随类型**：活动=1天/1小时/10分钟前，取件=失效前30分钟……而非一个闹钟；
5. **本地优先**：无账号、无云端、Release 不声明网络权限。

## 功能状态

| 功能 | 优先级 | 状态 |
|---|---|---|
| 时间解析引擎（14 类表达/年份推断/角色分类） | P0 | ✅ 62 项单测 |
| 确认/纠错页（OCR 高亮、低置信度标记、提醒预览） | P0 | ✅ |
| 卡片生命周期 + FreshnessPolicy | P0 | ✅ |
| 多锚点多 offset 提醒策略（安静时段/去重/跳过） | P0 | ✅ |
| SQLite 持久化 + 迁移（OHOS: sqflite_ohos / 桌面: ffi） | P0 | ✅ 已编译进 HAP，schema v2 |
| 图片沙箱复制/哈希/缩略图/级联清理 | P0 | ✅ |
| 系统分享接收 / Core Vision OCR / 代理提醒（ArkTS） | P0 | ✅ 已编译进 HAP（🟡 未真机运行验证） |
| 手动输入降级 / Mock 能力（Debug 横幅标注） | P0 | ✅ |
| 通知点击进卡片（wantAgent 深链） | P1 | ✅ 已编译（无自定义按钮，见下） |
| 实况窗倒计时 | P1 | 🟡 接口+flag，编译隔离，待权益 |
| Form Kit 服务卡片 | P1 | ⬜ 未实现（接口预留） |
| MindSpore 语义模型 | P2 | ⬜ 脚手架 |

> HAP 构建状态：**Debug 与 Release HAP 均编译 + 打包通过**（OHOS Flutter
> 3.35.8-ohos-1.0.1 + HarmonyOS SDK API 24），产物为**未签名** HAP，唯一未完成的
> 阶段是**签名**（需 DevEco 登录华为账号自动生成证书）。OCR/分享/代理提醒三条链
> 已真实编译进 HAP（制品字节码可见插件类，Live View 不在编译路径）。
> **无真机，所有运行期行为未验证。**
> 制品指纹与解包审计见 `docs/artifact-audit.md`，Release 前对抗式审计见
> `docs/adversarial-audit.md`，工具链细节见 `docs/hap-bringup-report.md`。
>
> | 制品 | 大小 | 完整 SHA-256（unsigned） |
> |---|---:|---|
> | Debug HAP | 95.2 MiB | `1efcc18da35d3ae46b07539bb64ba743d4ee371f36ab1f9773682f6fff41f0eb` |
> | Release HAP | 22.6 MiB | `7c70be29c4adc68e3b05cb7c1b7dbcd29625c0ec5daca63927370575566a4d9f` |
>
> SDK 版本（Release 合并 manifest）：compileSdkVersion `6.1.1.125` · compatible/target
> API 24 · ABI `arm64-v8a` · 权限仅 `PUBLISH_AGENT_REMINDER`（**无 INTERNET**）。

## 架构

Flutter（UI/解析/存储/提醒意图）↔ 4 条 Channel ↔ ArkTS（OCR/分享/代理提醒/实况窗）。
详见 `docs/architecture.md`；Flutter/ArkTS 边界与数据流图在其中。

## 环境与构建

- 开发/测试：**官方 Flutter 3.44.6（stable）** 桌面运行 analyze + 129 测试
  （仅此版本经过验证，未泛化到任意 3.4x）。
- **构建 HAP 使用 OHOS 分支**：<https://gitcode.com/CPF-Flutter/flutter_flutter>
  tag `3.35.8-ohos-1.0.1`（Dart 3.9.2）+ DevEco Studio + HarmonyOS SDK API 24。
  详细步骤与精确命令：`docs/hap-bringup-report.md`、`docs/native-integration.md`。

```bash
# 桌面开发/测试（官方 Flutter）
flutter pub get
tool/check.sh          # 格式化 + analyze + 119 测试
flutter run            # 桌面调试（显示“模拟能力”横幅）

# 构建 HAP（OHOS Flutter，环境变量见 hap-bringup-report §3）
export HOS_SDK_HOME=/path/to/DevEco/sdk
.toolchains/flutter-ohos/bin/flutter build hap --debug
# 产物: ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 真机权限

`ohos.permission.PUBLISH_AGENT_REMINDER`（代理提醒）+ 运行时
`requestEnableNotification`。图库用系统 Picker 免权限；分享经 Want 临时授权。
实况窗需 AGC 权益（实验 flag 默认关）。

## 鸿蒙能力集成状态

> 表述范围：本机 DevEco SDK（HarmonyOS 6.1.1 / API 24）中**存在本项目实际使用的
> 各 Kit 的声明与编译依赖**，并已随 HAP 编译。不宣称“含全部 HMS Kit”。

| Kit | 状态 |
|---|---|
| Core Vision 文字识别 | **已编译**（`@hms.ai.ocr.textRecognition`，cornerPoints→包围盒；无 confidence 返回 null）；未真机运行验证 |
| Share Kit 接收分享 | **已编译**（图库 PhotoViewPicker + Want/sendData skill 经 systemShare.getSharedData 接收）；未真机运行验证 |
| Reminder Agent | **已编译**（`@ohos.reminderAgentManager` 日历提醒 + wantAgent 深链）；本机 SDK `ActionButtonType` 仅 CLOSE/SNOOZE，**无自定义“完成/延后”通知按钮**——点击通知经 `freshcue://card/<id>` 深链进入卡片后在应用内完成/重排；未真机运行验证 |
| Live View Kit | 参考代码 + feature flag（默认关，编译隔离在 `ohos-reference/`），需权益 |
| Form Kit | 未实现（P1，接口预留） |

能力真实状态可在应用「设置 → 关于 →（连点）诊断页 → 原生能力握手」查看
（platform / API 版本 / 各 Kit 的 编译✓·可用✓·原因）。

## 隐私

数据不出设备；日志全量脱敏；敏感码遮罩显示；锁屏隐藏敏感通知；
删除卡片只清应用副本、不碰图库。详见 `docs/privacy-design.md`。

## 已知限制

见 `docs/known-limitations.md`（无真机导致的运行期未验证等，均如实标注）。
Release 前对抗式审计见 `docs/adversarial-audit.md`，HAP 制品解包审计见 `docs/artifact-audit.md`。

## 快速演示

**桌面 Mock 演示（非真机，不触发任何真实系统能力）**：
桌面 Debug 下首页空态点“用演示样例试一试” → 合成样张走 OCR/解析（Mock 通道，
黄色“模拟能力”横幅常驻） → 一图两时间确认 → 首页“截止还有 2 天” →
诊断页“测试提醒”仅在 Mock 中**登记**（不发真实系统通知） → 应用内标记完成 → 过期箱。
> 桌面演示中的 OCR / 分享 / 提醒**均为 Mock**，不代表真机行为。

**HarmonyOS 真机演示（全部步骤 ⏳ 待真机验证）**：
从其他应用系统分享图片冷启动 FreshCue → Core Vision OCR → 确认 →
代理提醒触发系统通知 → 点击通知经深链进入卡片 → 应用内完成 → 过期归档。
> 无设备，以上每一步均**待真机验证**，见 `docs/device-test-checklist.md`。
