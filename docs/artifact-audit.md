# HAP 制品审计（解包只读）

> 对干净 worktree @ HEAD `e5938d7` 产出的 Debug / Release **unsigned** HAP 解压只读审计。
> 命令：`unzip -q <hap> -d <dir>`；`module.json` 为**纯文本**合并 manifest（非二进制，无需反编译）。

## A. 制品指纹

| 制品 | 模式 | 大小 | 完整 SHA-256 | 签名 |
|---|---|---:|---|---|
| entry-default-unsigned.hap（Debug） | debug | 99,814,537 B | `4df3680651813ec0daecf68768784f1498a1dfb084cb765535848eac686e7163` | 未签名 |
| entry-default-unsigned.hap（Release） | release | 23,704,015 B | `2bee1dbd0d9f06e0eb63a90b50e69953c59d0f9f46459fec38e88c55e7f82563` | 未签名 |

> ⚠️ HAP 的 SHA-256 **非确定性**：zip 归档嵌入构建时间戳，同一 commit 逐次构建即得不同
> SHA（大小也有几十字节浮动）。上表指纹本次（HEAD `e5938d7`）产出的具体制品，不作
> “从源码可复现的确定性哈希”承诺。

## B. Bundle / Module / Ability（Release 合并 manifest）

- `bundleName`: `com.freshcue.app` · `versionName` 0.1.0 · `versionCode` 1 · `bundleType` app
- module: `entry`（type=entry, mainElement=EntryAbility, compileMode=esmodule, virtualMachine=ark24.0.0.0）
- ability: `EntryAbility`（`srcEntry ./ets/entryability/EntryAbility.ets`, exported=true）
- `deviceTypes`: `["phone"]`
- `installationFree`: false（非免安装）· `deliveryWithInstall`: true

## C. SDK 版本（制品级证据）

| 字段 | Debug | Release |
|---|---|---|
| `debug` | true | **false** |
| `buildMode` | debug | **release** |
| `apiReleaseType` | Debug | **Release** |
| `compileSdkVersion` | 6.1.1.125 | 6.1.1.125 |
| `minAPIVersion` / `targetAPIVersion` | 60101024 (API 24) | 60101024 (API 24) |
| pack.info `apiVersion.compatible/target` | 24 / 24 | 24 / 24 |

→ Release 包 `debug:false` + `buildMode:release` + `apiReleaseType:Release`，**不是重命名的 Debug 包**。

## D. ABI

- `libs/` 仅 `arm64-v8a`（Debug 与 Release 同）。
- 覆盖 Apple Silicon 模拟器（arm64）与主流 HarmonyOS 真机（arm64）。**无 armeabi-v7a / x86_64**。

## E. 权限（合并 manifest，非仅源码 module.json5）

- `requestPermissions`：**仅** `ohos.permission.PUBLISH_AGENT_REMINDER`。
- **无 `ohos.permission.INTERNET`**（`grep -o 'ohos.permission.[A-Z_]*' module.json` 只回一行）。
- Skills（EntryAbility）：
  - `entity.system.home` / `action.system.home`（入口）
  - `ohos.want.action.sendData` + `uris:[{scheme:file, utd:general.image, maxFileSupported:9}]`（**接收系统分享的图片**）
  - `ohos.want.action.viewData` + `uris:[{scheme:freshcue}]`（**通知深链** `freshcue://card/<id>`）
- 图库 `PhotoViewPicker` 与分享临时 URI 均**免声明权限**。

## F. Mock / Live View / 敏感物可达性

- 插件类字节码计数（`strings ets/modules.abc`）：`CapabilitiesPlugin`/`OcrPlugin`/`SharePlugin`/`ReminderPlugin` 各出现，`LiveView` **0 次** → 实况窗参考代码确未进入编译产物。
- Mock：Dart 侧 `shouldUseMockGateways(isDebug:false)→false`；Release 字节码走 `ChannelXGateway`。诊断页无启用 Mock 原生能力的入口（仅状态展示）。
- 无开发证书 / 私钥 / token / 真实用户路径 / 测试截图个人信息。唯一内置资产 `flutter_assets/assets/demo/campus_day.txt`（145 B，合成演示样张，无个人信息）。

## G. 体积（§17）

| 项 | Debug | Release |
|---|---:|---:|
| HAP 总大小 | 95.2 MiB | 22.6 MiB |
| `libs/arm64-v8a/libflutter.so` | 37.8 MB（含调试符号） | 15.8 MB（strip） |
| `flutter_assets/kernel_blob.bin`（JIT kernel，仅 Debug） | 47.5 MB | 无（AOT） |
| `flutter_assets/isolate_snapshot_data`（仅 Debug） | 10.9 MB | 无 |
| `libs/arm64-v8a/libapp.so`（AOT，仅 Release） | 无 | 7.2 MB |
| `ets/modules.abc`（ArkTS 字节码） | 1.09 MB | 0.64 MB |

→ Debug 95 MiB 的体积主要来自 JIT `kernel_blob.bin` + 未 strip 的调试引擎；Release AOT 后降至 22.6 MiB。**未**打包 demo 原图、测试 fixture、桌面动态库或重复字体（仅 1 份 MaterialIcons）。前一份报告“Debug HAP ~95MB”未区分 Release，已在本表更正。

## H. 结论

Release 制品级审计通过：真 Release 编译、arm64、单一提醒权限、无 INTERNET、无 Mock 可达路径、无 Live View、无秘密/个人数据。**可安装性结论：需签名后（DevEco 华为账号）方可安装；安装/运行行为 需设备验证。**
