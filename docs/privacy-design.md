# 隐私设计

原则：无账号、无云端、本地优先。分享给 FreshCue ≠ 允许进一步对外分享。

## 承诺与落实

| 规则 | 落实位置 |
|---|---|
| 不上传图片/OCR 文本/时间/地点/验证码 | 无任何网络代码；pubspec 无网络依赖 |
| Release 不声明网络权限 | `module.json5.reference` 无 INTERNET 类权限 |
| 沙箱图片不可预测文件名 | `ImageAssetService` 用 128-bit 随机 ID 命名 |
| 日志脱敏（验证码/手机号/身份证/银行卡/URL query） | `Redactor.redact`，`AppLog` 全部出口过 Redactor |
| 锁屏隐藏 temporary_secret 内容 | `ReminderPayload.hideContentOnLockScreen` + 通知正文只写“内容已隐藏” |
| 缩略图/缓存删除策略 | 删除卡片级联删除沙箱原图 + 缩略图（`CardService.deleteCard`） |
| 删除时告知删除范围 | 详情页删除确认框列明：卡片/提醒/OCR/应用内副本，不影响图库 |
| 崩溃日志不含完整 OCR 输入 | AppLog 只记录错误码与类型名，不记录 OCR 全文 |
| 演示数据与真实数据分离 | `ImportSource.demo` 标记；演示样例为合成内容 |
| 个人截图不进 Git | `.gitignore` + 测试 fixture 全部合成 |
| 分享 URI 只在导入期使用 | ArkTS 侧读 URI → 字节后立即交给沙箱复制，不保存授权 |
| 高风险信息（证件/银行卡）不建议保存 | 解析器 `highRisk` → 确认页红色警示 |

## 秘密值（验证码/入场码）处理链

保存原文（本地 SQLite）→ 列表/通知显示 `A•••1` 遮罩 → 详情页点眼睛短时显示 →
日志中永不出现原文。
