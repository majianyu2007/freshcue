#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/.toolchains/native-ocr"
build="$root/.build/native-ocr-smoke"
mkdir -p "$cache" "$build"

fetch_and_verify() {
  local url="$1"
  local output="$2"
  local checksum="$3"
  if [[ ! -f "$output" ]]; then
    curl -L --fail --retry 3 --output "$output" "$url"
  fi
  printf '%s  %s\n' "$checksum" "$output" | shasum -a 256 -c - >/dev/null
}

ncnn_zip="$cache/ncnn-20260526-apple.zip"
opencv_zip="$cache/opencv-mobile-4.13.0-macos.zip"
fetch_and_verify \
  "https://github.com/Tencent/ncnn/releases/download/20260526/ncnn-20260526-apple.zip" \
  "$ncnn_zip" \
  "bfd7188f0eda2c273c945496aaa9cd6eff5bea2a98f04c0200e37bb586a0a0bd"
fetch_and_verify \
  "https://github.com/nihui/opencv-mobile/releases/download/v36/opencv-mobile-4.13.0-macos.zip" \
  "$opencv_zip" \
  "5f510e607b0ff53c1a0b32e0c1dedad330b5e61ed5d7a81fe98c735df78badf8"
if [[ ! -d "$cache/ncnn.xcframework" ]]; then
  unzip -q "$ncnn_zip" -d "$cache"
fi
if [[ ! -d "$cache/opencv2.framework" ]]; then
  unzip -q "$opencv_zip" -d "$cache"
fi

ncnn_framework="$cache/ncnn.xcframework/macos-arm64_x86_64/ncnn.framework"
openmp_framework="$cache/openmp.xcframework/macos-arm64_x86_64/openmp.framework"
clang++ -std=c++17 -O2 -Wall -Wextra \
  -I"$root/ohos/entry/src/main/cpp" \
  -I"$ncnn_framework/Headers/ncnn" \
  -I"$cache/opencv2.framework/Headers" \
  "$root/tool/native_ocr_smoke.cpp" \
  "$root/ohos/entry/src/main/cpp/offline_ocr.cpp" \
  "$root/ohos/entry/src/main/cpp/ppocrv5.cpp" \
  -F"$(dirname "$ncnn_framework")" -framework ncnn \
  -F"$(dirname "$openmp_framework")" -framework openmp \
  -F"$cache" -framework opencv2 \
  -framework Accelerate \
  -o "$build/native_ocr_smoke"

cd "$root"
"$build/native_ocr_smoke" "ohos/entry/src/main/resources/rawfile/ocr"
