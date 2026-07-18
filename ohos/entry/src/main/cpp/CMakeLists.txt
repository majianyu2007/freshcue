cmake_minimum_required(VERSION 3.5.0)
project(freshcue_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

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
