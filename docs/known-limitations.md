# 已知限制

> 更新（Release 前对抗式审计阶段）：Debug 与 Release HAP 均**编译 + 打包通过**
> （3.35.8-ohos-1.0.1 / HarmonyOS SDK API 24），唯一未完成阶段是**签名**（需华为账号）。
> OCR/分享/代理提醒三条链已**真实编译**进 HAP（制品字节码可见插件类），数据库已切
> sqflite_ohos。剩余限制主要是**无真机导致的运行期未验证**。
> 详见 `docs/adversarial-audit.md`、`docs/artifact-audit.md`、`docs/hap-bringup-report.md`。

| # | 限制 | 原因 | 影响 | 下一步 |
|---|---|---|---|---|
| 1 | HAP 仅编译+打包，未签名 | 签名需 DevEco 登录华为账号自动生成证书（GUI，无法脚本化） | Debug（95.2 MiB）/ Release（22.6 MiB）unsigned HAP 均产出；`assembleHap` 成功，仅签名阶段被阻塞 | 有账号者 DevEco 打开 `ohos/` 配置自动签名后安装 |
| 2 | ArkTS 桥接未真机验证 | 无真机/模拟器（hdc 无目标） | OCR/分享/提醒已编译但未设备运行 | 真机按 device-test-checklist.md 逐项验证 |
| 3 | ~~main.dart 用内存仓库~~ **已解决** | — | OHOS 走 sqflite_ohos，桌面走内存 | 真机验证持久化 |
| 4 | 实况窗 feature flag 禁用 + 编译隔离 | 需 AGC 权益 | 实现留在 ohos-reference/，不阻塞 HAP | 取得权益后接入并验证 |
| 5 | Form Kit 服务卡片未实现（P1） | 本阶段禁止；HAP 优先 | 无桌面卡片 | HAP 三链验证后评估 |
| 6 | MindSpore 语义模型未训练（P2） | P0 优先；规则基线已可用 | 无模型推理 | ml/ 提供脚手架 |
| 7 | 多图分享只取第一张 | 第一版范围 | UI 有提示未导入张数 | P2 批量导入 |
| 8 | 跨设备协同通知未实现（P1 研究项） | 无多设备环境 | 无 | 待真机后调研 |
| 9 | 代理提醒无自定义通知按钮 | 本机 SDK ActionButtonType 仅 CLOSE/SNOOZE | “完成/延后”经点击通知进卡片在应用内完成 | 如需按钮，评估 Notification Kit 长驻方案（受进程存活限制） |
| 10 | OCR 无逐行置信度 | Core Vision recognizeText 结果不含 confidence | 置信度显示为空；解析用独立启发式分数 | 无（API 使然，如实呈现 null） |
| 11 | 图片方向（EXIF）依赖引擎解码 | 未真机验证特殊 EXIF | 极端旋转截图坐标可能偏移 | 真机用旋转样张验证 |
| 12 | getScheduledReminderIds 返回空 | 本机 getValidReminders 不暴露 reminderId | reconciliation 依赖 DB 存储的平台 ID（publishReminder 返回值），已足够 | — |

旧参考实现（基于不同 API 版本/文档）保存在 `ohos-reference/`，与本机 SDK 的差异
（ActionButtonType.CUSTOM 不存在、OCR itemRect vs cornerPoints、confidence 缺失等）
已在拉通阶段修正到 `ohos/entry/src/main/ets/plugins/` 的真实实现中。

（历史）`module.json5.reference` 中 Share Kit extensionAbilities 字段留空：不同 SDK
版本模板差异较大，接入时以 DevEco 模板 + 官方文档为准，不凭记忆硬写。
