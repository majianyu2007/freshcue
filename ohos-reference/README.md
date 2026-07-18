# ohos/ — HarmonyOS 原生工程（参考实现）

> ⚠️ **未真机验证**。本目录当前是 ArkTS 桥接的**参考实现**：本机没有 OHOS
> Flutter SDK 分支，无法运行 `flutter create --platforms ohos` 生成完整
> 工程模板，也无法编译 HAP。接入步骤见 `docs/native-integration.md`。

## 接入步骤概要

1. 安装 openharmony-sig Flutter（见 docs/feasibility-report.md §5）。
2. 在仓库根执行 `flutter create --platforms ohos .`，由官方模板生成
   完整 ohos 工程（build-profile、hvigor、AppScope 等）。
3. 把 `entry/src/main/ets/plugins/` 下的 4 个桥接类复制/合并进生成的工程，
   并在 `EntryAbility` 中注册（见 `entryability/EntryAbility.ets` 参考）。
4. 按 `module.json5.reference` 合并权限与 Share 接收配置。
5. `flutter build hap --debug`。

## 目录

- `entry/src/main/ets/plugins/` — 4 个 MethodChannel/EventChannel 桥接：
  - `OcrPlugin.ets` — Core Vision 文字识别（channel `freshcue/ocr`）
  - `SharePlugin.ets` — 分享接收/图库选择（channel `freshcue/share`）
  - `ReminderPlugin.ets` — 代理提醒（channel `freshcue/reminders`）
  - `LiveViewPlugin.ets` — 实况窗实验能力（channel `freshcue/live_view`）
- `entry/src/main/ets/entryability/EntryAbility.ets` — 注册与 Want 处理参考
- `entry/src/main/module.json5.reference` — 权限/技能声明参考

所有 API 名称以本地 SDK（OpenHarmony API 23）与官方文档为准；
若与实际 SDK 冲突，以编译结果为准并更新 `docs/known-limitations.md`。
