#!/usr/bin/env bash
# FreshCue 统一质量检查入口。遇错即停。
# 机器相关路径请放 tool/local.sh（已 gitignore），此处不硬编码。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/4 格式化检查"
dart format --output=none --set-exit-if-changed lib test || {
  echo "✗ 存在未格式化文件：运行 dart format lib test"; exit 1; }

echo "==> 2/4 flutter analyze"
flutter analyze

echo "==> 3/4 单元 + widget 测试"
flutter test

echo "==> 4/4 HAP 构建（可选，需 OHOS Flutter 环境）"
if command -v flutter >/dev/null && flutter config 2>/dev/null | grep -q 'enable-ohos: true' && [ -f ohos/build-profile.json5 ]; then
  flutter build hap --debug
else
  echo "跳过：本机无 OHOS Flutter 工具链（见 docs/native-integration.md）"
fi

echo "✓ 全部检查通过"
