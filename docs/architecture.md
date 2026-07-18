# 架构

## 数据流（核心闭环）

```
系统分享 / 图库导入
   │  (ArkTS SharePlugin：Want→字节，去重，冷/热启动)
   ▼
ImageAssetService  ──沙箱复制、MIME 魔数校验、SHA-256、缩略图
   ▼
OcrGateway (Core Vision / Mock)  ──文本块 + 归一化坐标
   ▼
ScreenshotParser（纯 Dart，本项目自研核心）
   span 提取 → 归一化/年份推断 → 角色分类 → 分类/字段提取 → ParsedDraft
   ▼
ReviewPage（确认/纠错，用户确认前不建提醒）
   ▼
CardService.confirmCard  ──卡片+计划+实例落库 → ReminderGateway 调度
   ▼
Reminder Agent（系统代理提醒）──通知行为 complete/snooze/view_source
   ▼
FreshnessPolicy（派生状态，不落库）──到期自动进过期箱
```

## 分层

| 层 | 目录 | 规则 |
|---|---|---|
| core | `lib/core/` | Clock/Result/AppFailure/日志脱敏/ID。无 Flutter 依赖（logging 除外） |
| domain | `lib/domain/` | 实体、枚举、解析器、策略、仓库接口。**纯 Dart，无平台依赖** |
| data | `lib/data/` | SQL/内存仓库、图片资产、CardService 编排 |
| platform | `lib/platform/` | 4 个 Gateway 接口 + Channel 实现 + Mock + Registry |
| app/features | `lib/app/ lib/features/` | ChangeNotifier 控制器 + 页面。页面不直接写 SQL |

## Flutter / ArkTS 边界

- Flutter：全部 UI、解析、存储决策、提醒意图管理（事实来源是数据库）。
- ArkTS（`ohos/entry/src/main/ets/plugins/`）：仅 4 件事 —— Core Vision OCR、
  分享接收/图库 Picker、代理提醒发布/取消/行为回传、实况窗。无 ArkUI 页面。
- 契约：`freshcue/ocr`、`freshcue/share`(+events)、`freshcue/reminders`(+events)、
  `freshcue/live_view`；错误一律映射稳定错误码（`channel_gateways.dart`）。

## 关键设计决策

1. **可注入 Clock**：领域层禁止 `DateTime.now()`；测试用 `FixedClock` 冻结时间。
2. **派生状态不落库**：fresh/upcoming/urgent/expired 由 `FreshnessPolicy` 实时计算。
3. **Plan/Instance 分离**：`ReminderPlan` 是意图（截止前 2 小时），
   `ReminderInstance` 是绝对触发时间 + 平台 ID + 状态。编辑时间 = 取消全部
   平台提醒 → 重新展开 → 原子替换实例。
4. **启动 reconciliation**：清理过期 scheduled 实例、为缺平台 ID 的未来实例补建。
5. **Mock 防线**：`PlatformRegistry` 在 Release 断言禁止 Mock；Debug 下 Mock
   激活时 UI 常驻黄色横幅。
6. **数据库注入**：仓库编码到 `sqflite_common` API；测试注入
   `sqflite_common_ffi`，OHOS 真机注入 openharmony-sig sqflite 的 factory。
