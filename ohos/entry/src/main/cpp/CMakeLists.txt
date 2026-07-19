cmake_minimum_required(VERSION 3.5.0)
project(freshcue_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ncnn exposes OpenMP as a transitive dependency. Hvigor records the SDK
# libomp.so as a runtime file but does not copy it into Flutter-built HAPs,
# which makes libentry.so fail to load on device. Link the SDK's static OpenMP
# runtime so the OCR module remains self-contained.
set(OpenMP_omp_LIBRARY
    "${OHOS_SDK_NATIVE}/llvm/lib/aarch64-linux-ohos/libomp.a"
    CACHE FILEPATH "HarmonyOS static OpenMP runtime" FORCE)

set(ncnn_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ncnn-20260526-harmonyos/${OHOS_ARCH}/lib/cmake/ncnn")
find_package(ncnn REQUIRED)

set(OpenCV_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/opencv-mobile-4.13.0-harmonyos/${OHOS_ARCH}/lib/cmake/opencv4")
find_package(OpenCV REQUIRED core imgproc)

add_library(entry SHARED
    napi_init.cpp
    offline_ocr.cpp
    ppocrv5.cpp
)

target_compile_options(entry PRIVATE -Wall -Wextra)
target_link_options(entry PRIVATE -Wl,--gc-sections)
target_link_libraries(entry PUBLIC libace_napi.z.so ncnn opencv_core opencv_imgproc)
