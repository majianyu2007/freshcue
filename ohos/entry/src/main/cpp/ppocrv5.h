// Tencent is pleased to support the open source community by making ncnn available.
//
// Copyright (C) 2025 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the BSD 3-Clause License. See THIRD_PARTY_NOTICES.txt.
// Adapted for FreshCue from nihui/ncnn-android-ppocrv5 revision
// 671ac4a72299a86ddee160131ba88fed748df425.

#ifndef FRESHCUE_PPOCRV5_H
#define FRESHCUE_PPOCRV5_H

#include <cstddef>
#include <string>
#include <vector>

#include <opencv2/core/core.hpp>
#include <net.h>

namespace freshcue {

struct OcrObject {
    cv::RotatedRect rrect;
    int orientation = 0;
    float detectionScore = 0.0f;
    float tokenScore = 0.0f;
    std::string text;
};

class PPOCRv5 {
public:
    PPOCRv5();

    bool load(const char* detParam, const unsigned char* detModel,
              const char* recParam, const unsigned char* recModel);
    bool loadFromFiles(const char* detParamPath, const char* detModelPath,
                       const char* recParamPath, const char* recModelPath);
    void clear();
    void setTargetSize(int targetSize);

    bool detect(const cv::Mat& rgb, std::vector<OcrObject>& objects) const;
    bool recognize(const cv::Mat& rgb, OcrObject& object) const;

private:
    ncnn::Net detector_;
    ncnn::Net recognizer_;
    int targetSize_;
};

}  // namespace freshcue

#endif
