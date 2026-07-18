# Changelog

## 0.1.0 — 2026-07-18

### Phase 0 环境勘察
- 可行性报告（docs/feasibility-report.md）：官方 Flutter 3.44.6（非 OHOS 分支，
  无法构建 HAP）、DevEco + OpenHarmony SDK API 23 就绪、无真机。

### Phase 1 领域层
- TemporalCard/SourceAsset/OcrBlock/TemporalCandidate/ReminderPlan/Instance；
- 可注入 Clock；FreshnessPolicy（派生状态不落库）；ReminderPolicy
  （分类模板/展开/去重/跳过/安静时段/snooze）；内存仓库。

### Phase 3 时间解析引擎（自研核心）
- span 提取（绝对/月日/相对/星期/时间段/日期区间）→ 锚定归一化
  （年份推断、跨年提示、历史截图容错、闰年）→ 角色分类（距离衰减关键词，
  发布时间排除）→ 卡片分类 → 标题/地点/临时码提取 → 置信度与可解释输出。
- 62 项解析单测（含全部 12 个规定边界用例）。

### Phase 2 数据层
- SQLite schema v1 + 迁移机制（sqflite_common，ffi 真库测试）；
- 图片沙箱复制（魔数校验/SHA-256/缩略图/失败回滚）；
- CardService：确认→调度、编辑→取消重建、删除级联、通知行为、reconciliation。

### Phase 4-5 平台桥接
- 4 个 Gateway 接口 + MethodChannel 实现（稳定错误码映射）+ Debug Mock；
- PlatformRegistry：Release 禁 Mock、Debug Mock 显横幅；
- ArkTS 参考实现（OCR/Share/Reminder/LiveView + EntryAbility 深链分发），
  **未真机验证**。

### Phase 6 UI
- 首页（筛选/排序/空态）、导入流程（图库/手动/演示 + 四阶段处理页）、
  确认页（原图高亮/低置信度标记/提醒预览/安静时段说明）、详情页
  （时间线/完成/归档/删除/改时间/实况入口）、过期箱（恢复/删除副本）、
  设置、诊断（能力检测/脱敏错误/演示提醒）、三屏引导、深色模式、深链路由。

### 测试与工具
- 107 测试全通过；flutter analyze 0 issues；tool/check.sh；
  全套文档（架构/隐私/测试/原生集成/依赖审计/已知限制/演示脚本/真机清单）。
