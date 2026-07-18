# 已知限制

| # | 限制 | 原因 | 影响 | 下一步 |
|---|---|---|---|---|
| 1 | HAP 未构建 | 本机无 OHOS Flutter SDK 分支 | 无法出包 | 按 native-integration.md §1-2 在配好环境的机器执行 |
| 2 | 全部 ArkTS 桥接未真机验证 | 无真机/模拟器 | OCR/分享/提醒/实况窗为参考实现 | 真机按 device-test-checklist.md 逐项验证 |
| 3 | 当前 main.dart 使用内存仓库 | sqflite-ohos 需真机工程 | 桌面演示重启丢数据；SQL 层已完成并通过 ffi 测试 | 真机接线见 native-integration.md §3 |
| 4 | 实况窗 feature flag 禁用 | 需要 AGC 测试/正式权益 | 设置页开关为禁用态 | 取得权益后启用并真机验证 |
| 5 | Form Kit 服务卡片未实现（P1） | Flutter 容器集成风险 + 无环境 | 无桌面卡片 | 接口预留（快照写入方案见 architecture.md），独立 flag |
| 6 | MindSpore 语义模型未训练（P2） | P0 优先；规则基线已可用 | 无模型推理 | ml/ 提供可复现训练脚手架 |
| 7 | 多图分享只取第一张 | 第一版范围 | UI 有提示未导入张数 | P2 批量导入 |
| 8 | 跨设备协同通知未实现（P1 研究项） | 无多设备环境 | 无 | 待真机后调研 notification-distributed API |
| 9 | OCR 逐行置信度取保守常量 0.9 | Core Vision line 级置信度以真机 SDK 为准 | 置信度显示偏保守 | 真机确认 API 字段后替换 |
| 10 | 图片方向（EXIF）规范化依赖引擎解码 | instantiateImageCodec 自动处理常见方向；特殊 EXIF 未验证 | 极端旋转截图坐标可能偏移 | 真机用旋转样张验证 |

`module.json5.reference` 中 Share Kit extensionAbilities 字段留空：不同 SDK
版本模板差异较大，接入时以 DevEco 模板 + 官方文档为准，不凭记忆硬写。
