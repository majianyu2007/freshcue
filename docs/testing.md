# 测试说明

## 运行

```bash
flutter analyze        # 0 issues
flutter test           # 107 个测试
tool/check.sh          # 格式化 + analyze + test 一键
```

## 覆盖矩阵

| 套件 | 文件 | 数量 | 覆盖 |
|---|---|---|---|
| 解析器 | test/parser/parser_test.dart | 62 | 全部 §14.2 时间表达、年份推断/跨年/闰年、区间、角色分类（含发布时间排除）、OCR 重复去重、卡片分类、标题/地点/验证码提取、高风险检测、12 个规定边界用例、演示样例 |
| 领域 | test/domain/domain_test.dart | 19 | FreshnessPolicy 四状态边界、提醒模板展开、跳过过去、去重、安静时段、snooze、敏感遮罩 |
| 数据 | test/data/database_test.dart | 9 | 真实 SQLite（ffi）：schema、全字段读写、按状态查询、sha256 去重、计划/实例替换、级联删除、损坏记录容错、跨连接持久化 |
| 服务 | test/data/card_service_test.dart | 7 | 确认→调度、编辑→取消重建、删除级联、通知行为、snooze、reconciliation、调度失败不装成功 |
| Widget | test/widgets/app_widget_test.dart | 10 | 首页空/有数据、Mock 横幅、敏感遮罩、确认页低置信度+多时间+提醒预览、权限拒绝降级、深色模式、1.6x 大字体、过期箱恢复、通知 complete |

## 约定

- 所有时间敏感测试使用 `FixedClock`（锚点 2026-07-18 10:00），零 `DateTime.now()`。
- 数据库测试用 `sqflite_common_ffi`（与 OHOS sqflite 插件同一 API 面）。
- 集成/真机测试见 `docs/device-test-checklist.md`（当前全部未验证）。
