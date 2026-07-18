# 原生集成指南（OHOS）

> 状态更新：OHOS 工具链已在本机跑通，HAP 可构建，OCR/分享/代理提醒三条链
> **已真实编译进 HAP**（详见 `docs/hap-bringup-report.md`）。本文覆盖：命令行构建、
> **用 DevEco 打开 `ohos/` + 签名 + 跑模拟器**、各能力接线要点。运行期行为
> （真机 OCR/分享/提醒触发）仍未真机验证，见 `docs/device-test-checklist.md`。

## 1. 工具链（已固定）

- OHOS Flutter：<https://gitcode.com/CPF-Flutter/flutter_flutter> tag
  `3.35.8-ohos-1.0.1`（Dart 3.9.2），安装于 `.toolchains/flutter-ohos`（gitignore）。
- SDK：DevEco Studio 内置 **HarmonyOS 6.1.1 / API 24**（`/Applications/DevEco-Studio.app/Contents/sdk`）。
- 构建工具：DevEco 内置 hvigor / ohpm / node v18。

环境变量已写入 `~/.zshrc`（标记块 `FreshCue HarmonyOS Toolchain`），提供 `hflutter`
别名（带国内镜像 + DevEco node v18，不污染全局）。新终端直接可用：

```bash
cd ~/Project/freshcue
hflutter build hap --debug
# 产物: ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

全新环境的搭建步骤与精确版本矩阵见 `docs/hap-bringup-report.md` §1–3。

## 2. 命令行构建 HAP

```bash
hflutter build hap --debug     # Debug，未签名
# Release 需先在 DevEco 配置签名（见 §3），再：
hflutter build hap --release
```

`hflutter` 会经 `flutterHvigorPlugin`（根 `ohos/hvigorfile.ts` 已挂）自动先构建
Dart 代码，再由 hvigor assembleHap。

## 3. 用 DevEco 打开 `ohos/` + 签名 + 跑模拟器

### 3.1 打开正确的目录

DevEco 靠工程根的 `build-profile.json5` / `oh-package.json5` / `AppScope/` 识别
HarmonyOS 工程——这些在 **`ohos/` 子目录**里，不在仓库根。

> DevEco → 打开项目 → 选择 **`<仓库根>/ohos`**（即 `$HOME/Project/freshcue/ohos`
> 之类的本机路径；选仓库根会报「不是 OpenHarmony/HarmonyOS 项目」，因为根是 Flutter 工程）。

已就绪、无需手动：
- `ohos/local.properties`（机器相关，已 gitignore）指向 DevEco SDK 与 OHOS Flutter。
- `compatibleSdkVersion` / `targetSdkVersion` = `6.1.1(24)`，匹配已装 SDK，
  同步不会去下载其它 API 版本。
- 根 hvigorfile 挂了 `flutterHvigorPlugin`——点 Run 会自动构建 Dart，不必先手动跑 flutter。

### 3.2 配置调试签名（唯一必须手动的一步）

模拟器/真机安装都需要签名的 HAP。`build-profile.json5` 的 `signingConfigs` 目前为空，
由 DevEco 自动生成填充（需登录华为账号）：

1. 菜单 **File → Project Structure（项目结构）→ Signing Configs**
2. 勾选 **Automatically generate signature（自动生成签名）**
3. 确定后 `signingConfigs` 会被填充；**私钥/证书不要提交 Git**
   （`.gitignore` 已忽略 `ohos/**/signingConfigs/` 与 `*.p12/*.cer/*.p7b` 等）。

### 3.3 启动模拟器并运行

1. **Device Manager**（工具栏设备图标）启动已安装的模拟器（Apple Silicon 为 arm64，
   与构建目标 `ohos-arm64` 一致）。
2. 顶部工具栏选中该模拟器 → 点 **Run（▶）**。
3. 首次 Run：DevEco 跑 hvigor sync + flutter build（引擎产物已缓存，不重新下载），
   装签名后的 HAP 并启动。

命令行安装校验（模拟器已启动时）：

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC list targets                       # 应列出模拟器
$HDC install <签名后的.hap>              # 或直接在 DevEco 里 Run
```

### 3.4 验证原生能力

应用内「设置 → 关于 →（连点版本号）诊断页 → 原生能力握手」应显示
`platform=ohos · API 24`，OCR/分享/代理提醒 `编译✓`，可用状态视设备/权限而定。

## 4. 各能力接线要点（与本仓库真实实现一致）

### OCR（Core Vision）
- `@kit.CoreVisionKit` → `@hms.ai.ocr.textRecognition.recognizeText(VisionInfo): Promise`。
- 结果 `blocks[].lines[]` 用 **cornerPoints 多边形**，`OcrPlugin` 换算为 0~1 归一化包围盒。
- **无逐行 confidence**：返回 null，不伪造（Dart 侧 `OcrResultBlock.confidence` 可空）。
- 免权限；不可用时 Flutter 降级手动输入。

### 分享接收 + 图库
- 图库：`photoAccessHelper.PhotoViewPicker`（系统 Picker，免权限）。
- 分享接收：`module.json5` 声明 `ohos.want.action.sendData` skill（uri `scheme:file, utd:general.image`）；
  `EntryAbility.onCreate/onNewWant` 分发 Want → `SharePlugin` 用
  `systemShare.getSharedData(want)` 还原记录，URI 立即读为字节（不留授权），UUID 去重。
- 这是 Want/Ability 级接收，非 ShareKit 发送 API。

### 代理提醒（Reminder Agent）
- 权限 `ohos.permission.PUBLISH_AGENT_REMINDER`（安装期授予）+ 运行时
  `notificationManager.requestEnableNotification()`。
- `reminderAgentManager.publishReminder(ReminderRequestCalendar)` 返回 reminderId（存 DB）。
- **本机 SDK 的 `ActionButtonType` 仅 CLOSE/SNOOZE，无自定义按钮**：不做「完成/延后」
  通知按钮；改用 `wantAgent(uri=freshcue://card/<id>)`，点击通知拉起
  `EntryAbility` → 分发深链 → Flutter 打开卡片，在应用内完成/延后。
- `getScheduledReminderIds` 返回空（本机 `getValidReminders` 不暴露 reminderId），
  reconciliation 依赖 DB 存储的平台 ID。

### 实况窗（Live View Kit）
- 需 AGC 权益；默认 feature flag 关闭，实现编译隔离在 `ohos-reference/`，不阻塞 HAP。

## 5. 数据库（已接入，无需再改）

已在 `pubspec.yaml` 用 git 依赖引入 OHOS 适配 sqflite（CPF-Flutter/flutter_sqflite
branch `br_v2.4.2_ohos` @ `1eefac74916ee14cab6b58da4d60a84153bcb758`），
`sqflite_ohos` 随 `GeneratedPluginRegistrant` 编入 HAP。`lib/main.dart` bootstrap
依据 capability handshake 选择：

- OHOS（`caps.isOhos && filesDir != null`）→ `sqflite.databaseFactory` +
  `<filesDir>/db/freshcue.db`，沙箱图片写 `<filesDir>/assets`。
- 桌面/测试 → 内存仓库（Release 走不到此分支）。

schema 版本 v2（ocr_blocks.confidence 可空的迁移已含冒烟测试）。
