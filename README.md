# 截期 FreshCue

> 把截图中的临时信息转换成会提醒、会过期的时效卡片。
> *Turn screenshots into timely, expiring cards.*

（产品截图占位：首页 / 确认页 / 通知 —— 待真机构建后补充）

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
| SQLite 持久化 + 迁移（sqflite_common，ffi 测试） | P0 | ✅（真机接线待做） |
| 图片沙箱复制/哈希/缩略图/级联清理 | P0 | ✅ |
| 系统分享接收 / Core Vision OCR / 代理提醒（ArkTS） | P0 | 🟡 参考实现，未真机验证 |
| 手动输入降级 / Mock 能力（Debug 横幅标注） | P0 | ✅ |
| 通知完成/延后行为 | P1 | ✅ Flutter 侧 + ArkTS 参考 |
| 实况窗倒计时 | P1 | 🟡 接口+flag，待权益 |
| Form Kit 服务卡片 | P1 | ⬜ 未实现（接口预留） |
| MindSpore 语义模型 | P2 | ⬜ 脚手架 |

## 架构

Flutter（UI/解析/存储/提醒意图）↔ 4 条 Channel ↔ ArkTS（OCR/分享/代理提醒/实况窗）。
详见 `docs/architecture.md`；Flutter/ArkTS 边界与数据流图在其中。

## 环境与构建

- 开发/测试：任意 Flutter 3.4x stable（本仓库在 3.44.6 验证）。
- **构建 HAP 必须使用 OHOS 分支**：<https://gitee.com/openharmony-sig/flutter_flutter>
  + DevEco Studio + OpenHarmony SDK（本机为 API 23）。步骤：`docs/native-integration.md`。

```bash
flutter pub get
tool/check.sh          # 格式化 + analyze + 107 测试
flutter run            # 桌面调试（显示“模拟能力”横幅）
flutter build hap --debug   # 仅 OHOS 环境（见 docs/feasibility-report.md §5）
```

## 真机权限

`ohos.permission.PUBLISH_AGENT_REMINDER`（代理提醒）+ 运行时
`requestEnableNotification`。图库用系统 Picker 免权限；分享经 Want 临时授权。
实况窗需 AGC 权益（实验 flag 默认关）。

## 鸿蒙能力集成状态

| Kit | 状态 |
|---|---|
| Core Vision 文字识别 | ArkTS 参考实现（OcrPlugin.ets），未真机验证 |
| Share Kit 接收分享 | ArkTS 参考实现（冷/热启动/去重/多图提示），未真机验证 |
| Background Tasks / Reminder Agent | ArkTS 参考实现（日历型+行为按钮+深链），未真机验证 |
| Live View Kit | 参考实现 + feature flag（默认关），需权益 |
| Form Kit | 未实现（P1，接口预留） |

## 隐私

数据不出设备；日志全量脱敏；敏感码遮罩显示；锁屏隐藏敏感通知；
删除卡片只清应用副本、不碰图库。详见 `docs/privacy-design.md`。

## 已知限制

见 `docs/known-limitations.md`（HAP 未构建、ArkTS 未真机验证等 10 项，均如实标注）。

## 快速演示

分享合成样张 → 一图两时间确认 →
首页“截止还有 2 天” → 诊断页真实 5 分钟提醒 → 通知完成 → 过期箱。
桌面 Debug 下可在首页空态点“用演示样例试一试”走完整链路。
