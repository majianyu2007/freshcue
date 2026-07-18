# 原生集成指南（OHOS）

> 本机（macOS，官方 Flutter stable）未安装 OHOS Flutter 分支，以下步骤
> 在具备环境的机器上执行。全部 ArkTS 代码目前为**参考实现，未真机验证**。

## 1. 环境

```bash
git clone https://gitee.com/openharmony-sig/flutter_flutter.git ~/ohos-flutter
export PATH=~/ohos-flutter/bin:$PATH
export TOOL_HOME=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$TOOL_HOME/sdk
export PATH=$TOOL_HOME/tools/ohpm/bin:$TOOL_HOME/tools/hvigor/bin:$PATH
flutter config --enable-ohos
flutter doctor   # 确认出现 ohos toolchain
```

## 2. 生成 ohos 工程并合并桥接

```bash
flutter create --platforms ohos .
```

然后把 `ohos/entry/src/main/ets/plugins/` 的 4 个插件与
`entryability/EntryAbility.ets` 合并进生成的工程；按
`module.json5.reference` 合并权限与 skills；`AppScope/app.json5` 的
bundleName 设为 `com.freshcue.app`。

## 3. 数据库切换（sqflite → OHOS）

真机构建加入 openharmony-sig 适配的 sqflite（在
gitee.com/openharmony-sig/flutter_packages 中，锁定 commit）：

```yaml
dependency_overrides:
  sqflite:
    git:
      url: https://gitee.com/openharmony-sig/flutter_packages.git
      path: packages/sqflite/sqflite
      ref: <验证过的 commit>
```

`main.dart` 中：

```dart
import 'package:sqflite/sqflite.dart' show databaseFactory;
final db = await openAppDatabase(databaseFactory, join(appFilesDir, 'freshcue.db'));
// 用 Sql*Repository 替换 createMemoryAppController 中的 Memory* 仓库
```

沙箱目录使用 ArkTS 侧传入的 `context.filesDir`（可再加一个简单 channel 或
用 path_provider 的 ohos 适配版）。

## 4. 各能力接线要点

### OCR（Core Vision）
- `@kit.CoreVisionKit` `textRecognition.recognizeText(VisionInfo)`。
- 坐标：ArkTS 侧换算为 0~1 归一化（OcrPlugin 已做）。
- 免权限；不可用时 Flutter 自动降级手动输入。

### 分享接收（Share Kit）
- `module.json5` 声明图片类接收（以当前 SDK 模板字段为准）。
- 冷启动：`onCreate` Want → `getInitialShare` 排队；热启动：`onNewWant` → EventChannel。
- URI 立即读为字节（不留授权）；重复 Want 以 UUID 去重。

### 代理提醒（Reminder Agent）
- 权限 `ohos.permission.PUBLISH_AGENT_REMINDER` + `requestEnableNotification`。
- `ReminderRequestCalendar` + actionButton 深链
  `freshcue://action/<complete|snooze_10m>/<cardId>/<instanceId>`。
- EntryAbility 解析行为 Want → ReminderPlugin.emitAction（冷启动排队补发，
  key 去重保证只执行一次）。

### 实况窗（Live View Kit）
- 需 AGC 权益；默认 feature flag 关闭（设置页开关禁用态）。
- 仅前台、用户点击后创建；失败错误码回退普通通知。

## 5. 构建

```bash
flutter build hap --debug
# Release：在 DevEco 中配置签名（signingConfigs 不入库）后
flutter build hap --release
hdc install entry/build/default/outputs/default/*.hap
```
