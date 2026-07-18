# Changelog

## Unreleased — Release 前对抗式审计（feat/ohos-hap-bringup）

### 修复
- **组合根数据安全**：OHOS 持久化后端改由 `Platform.operatingSystem=='ohos'` 决定，
  不再依赖 OCR/分享/提醒 capability 握手——修复“握手超时/失败静默降级内存仓库丢数据”
  缺陷；OHOS 运行期缺沙箱目录或 SQL 打开失败 → 阻塞错误页，绝不静默用内存。
- 抽出纯函数 `choosePersistence` / `shouldUseMockGateways`（可单测，覆盖 Release 配置对象）。

### 测试
- 新增 10 项：8 组合根决策（含 Release 禁 Mock）+ 2 通知深链安全失败。总数 119→**129**，
  官方 Flutter 3.44.6 与 OHOS Flutter 3.35.8-ohos-1.0.1 双工具链各全绿。

### 构建 / 制品
- **Release HAP 首次构建**：干净 worktree 产出 unsigned Debug（95.2 MiB）+ Release（22.6 MiB），
  完整 SHA-256 与解包审计见 `docs/artifact-audit.md`；两模式 `assembleHap` 成功，仅签名被阻塞。
- Release 合并 manifest 审计：`debug:false`/`buildMode:release`、权限仅 `PUBLISH_AGENT_REMINDER`
  （无 INTERNET）、ABI `arm64-v8a`、compileSdkVersion 6.1.1.125、compatible/target API 24；
  字节码含 4 插件类、无 Live View。

### 文档纠错
- 新增 `docs/adversarial-audit.md`（12 问题 + 声明—证据账本）、`docs/artifact-audit.md`。
- README/known-limitations/testing/native-integration/hap-bringup/device-checklist/dependency-audit
  纠正：HAP 状态、桌面 Mock vs 真机演示分离、Flutter 版本不泛化、HMS Kit 不宣称“全部”、
  通知无自定义按钮、完整 SHA、测试计数、依赖许可证 MIT→BSD-2-Clause、API since 矩阵。

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
