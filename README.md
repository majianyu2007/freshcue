# FreshCue（截期）

FreshCue 把截图中的短期信息（活动、取件码、票务、截止事项等）转换为可编辑的时效卡片，并在端侧完成 OCR、中文时间解析、提醒和到期归档。应用不要求账号，不使用云端服务，也不申请网络权限。

## 当前状态

截至 2026-07-19：

- Flutter 界面、SQLite 数据层、规则解析器和卡片生命周期已实现。
- HarmonyOS NEXT 原生桥接已实现：图片选择/系统分享接收、离线 OCR、代理提醒、服务卡片。
- 离线 OCR 使用 PaddleOCR PP-OCRv5 mobile detection → recognition 流水线、ncnn 与 opencv-mobile；无网络回退。
- Debug 与 Release HAP 均可完成编译和打包；当前产物未签名，需在 DevEco Studio 中配置签名。
- 自动化测试 136 项通过、静态分析 0 issues；原生 det → rec smoke gate 的 10 类合成截图通过 9 类（见 `docs/testing.md`）。
- 未连接 HarmonyOS 设备，因此 OCR、分享、提醒、SQLite 持久化和服务卡片的设备运行行为仍待验证。
- 实况窗未实现：本机 SDK 表明第三方普通应用不能直接创建系统实况窗，项目已删除不可用接口和占位实现。

## 核心流程

```text
图库/系统分享 → 图片沙箱副本 → 离线 OCR → 中文时间解析
             → 用户确认/编辑 → SQLite 卡片 → 代理提醒
             → 首页/详情/服务卡片 → 完成或到期归档
```

解析器识别多个时间角色，包括报名截止、活动开始、活动结束、失效时间和发布时间。正则仅定位时间片段；年份推断、跨年/闰年处理、角色分类和字段提取由独立阶段完成。

## 快速开始

### 桌面开发与测试

已验证工具链：Homebrew Flutter 3.44.6，Dart 3.12.x。

```bash
flutter pub get
tool/check.sh          # 格式检查 + flutter analyze + flutter test
flutter run            # 桌面调试；原生能力使用明确标记的 Mock
tool/native_ocr_smoke.sh  # 真实 ncnn det → rec；缓存固定版本 macOS 依赖到 .toolchains/
```

### HarmonyOS HAP

已验证工具链：CPF-Flutter 3.35.8-ohos-1.0.1，DevEco Studio HarmonyOS 6.1.1 / API 24。

```bash
hflutter build hap --debug
hflutter build hap --release
```

未签名产物：

```text
ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

Flutter 包装命令会在 `assembleHap` 成功后因缺少签名配置返回非零。安装前用 DevEco Studio 打开 `ohos/`，在 **File → Project Structure → Signing Configs** 中配置自动签名。切换桌面 Flutter 与 OHOS Flutter 后，如遇 shader 缓存不兼容，先执行对应工具链的 `flutter clean`。

## 目录

- `lib/core/`：时钟、结果/错误、日志脱敏、ID。
- `lib/domain/`：纯 Dart 实体、策略和解析管线。
- `lib/data/`：SQLite/内存仓库、图片资产、卡片编排。
- `lib/platform/`：Gateway、MethodChannel、Mock、能力握手。
- `lib/app/`、`lib/features/`：组合根、控制器和界面。
- `ohos/entry/src/main/ets/`：ArkTS Ability、插件和服务卡片。
- `ohos/entry/src/main/cpp/`：ncnn 离线 OCR N-API 模块。
- `test/`：领域、数据、平台和 Widget 测试。

## 文档

- [Repository Guidelines](AGENTS.md)：协作和代码约定。
- [Architecture](docs/architecture.md)：分层、数据流和关键不变量。
- [Native Integration](docs/native-integration.md)：HarmonyOS 桥接、OCR、提醒、服务卡片和构建。
- [Testing](docs/testing.md)：质量门、覆盖范围和设备验收清单。

## 隐私与限制

- 图片、OCR 文本、时间、地点和验证码仅保存在应用沙箱；合并 HAP manifest 不含 `ohos.permission.INTERNET`。
- 日志统一经过 `Redactor`；敏感卡片的通知内容被遮罩。
- 删除卡片会取消提醒并删除 OCR 记录及应用沙箱副本，不影响系统图库原图。
- 多图分享当前只导入第一张；UI 会提示其余图片未导入。
- Core Vision 不提供逐行置信度；离线模型的平均 token score 未校准，只用于原生低质量过滤且不跨桥传递。两者的逐行 `confidence` 均保持 `null`。

第三方 OCR 模型和 ncnn 的版权声明及许可证随 HAP 资源保存在 `ohos/entry/src/main/resources/rawfile/ocr/`。
