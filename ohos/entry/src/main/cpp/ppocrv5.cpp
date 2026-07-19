// Tencent is pleased to support the open source community by making ncnn available.
//
// Copyright (C) 2025 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the BSD 3-Clause License. See THIRD_PARTY_NOTICES.txt.
// Detector preprocessing, DB map postprocessing, rotated crops, and CTC decoding
// are adapted from nihui/ncnn-android-ppocrv5 revision
// 671ac4a72299a86ddee160131ba88fed748df425.

#include "ppocrv5.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include <opencv2/imgproc/imgproc.hpp>

#include "cpu.h"
#include "ppocrv5_dict.h"

namespace freshcue {
namespace {

double contourScore(const cv::Mat& probability, const std::vector<cv::Point>& contour) {
    cv::Rect rect = cv::boundingRect(contour);
    rect &= cv::Rect(0, 0, probability.cols, probability.rows);
    if (rect.empty()) {
        return 0.0;
    }

    cv::Mat mask = cv::Mat::zeros(rect.height, rect.width, CV_8U);
    std::vector<cv::Point> localContour;
    localContour.reserve(contour.size());
    for (const cv::Point& point : contour) {
        localContour.emplace_back(point.x - rect.x, point.y - rect.y);
    }
    const std::vector<std::vector<cv::Point>> contours = {std::move(localContour)};
    cv::fillPoly(mask, contours, cv::Scalar(255));
    return cv::mean(probability(rect), mask).val[0] / 255.0;
}

cv::Mat rotateCrop(const cv::Mat& rgb, const OcrObject& object) {
    const float shortSide = object.rrect.size.width;
    const float longSide = object.rrect.size.height;
    if (shortSide <= 0.0f || longSide <= 0.0f) {
        return {};
    }

    constexpr int kTargetHeight = 48;
    const int targetWidth = std::clamp(
        static_cast<int>(std::round(longSide * kTargetHeight / shortSide)),
        kTargetHeight, 1280);

    cv::Point2f corners[4];
    object.rrect.points(corners);
    std::vector<cv::Point2f> source(3);
    if (object.orientation == 0) {
        source[0] = corners[0];
        source[1] = corners[1];
        source[2] = corners[3];
    } else {
        source[0] = corners[2];
        source[1] = corners[3];
        source[2] = corners[1];
    }
    // OpenCV Mobile's KleidiCV dispatcher selects SVE2 on the HarmonyOS
    // emulator although that image cannot execute every SVE2 instruction.
    // This small portable sampler avoids an unrecoverable SIGILL in
    // cv::warpAffine while preserving bilinear interpolation and replicated
    // borders. NCNN still handles the expensive detector/recognizer work.
    cv::Mat crop(kTargetHeight, targetWidth, CV_8UC4);
    const cv::Point2f horizontal =
        (source[1] - source[0]) / static_cast<float>(targetWidth);
    const cv::Point2f vertical =
        (source[2] - source[0]) / static_cast<float>(kTargetHeight);
    for (int y = 0; y < kTargetHeight; ++y) {
        cv::Vec4b* output = crop.ptr<cv::Vec4b>(y);
        for (int x = 0; x < targetWidth; ++x) {
            const cv::Point2f point = source[0] + horizontal * x + vertical * y;
            const float sourceX = std::clamp(point.x, 0.0f,
                                             static_cast<float>(rgb.cols - 1));
            const float sourceY = std::clamp(point.y, 0.0f,
                                             static_cast<float>(rgb.rows - 1));
            const int x0 = static_cast<int>(std::floor(sourceX));
            const int y0 = static_cast<int>(std::floor(sourceY));
            const int x1 = std::min(x0 + 1, rgb.cols - 1);
            const int y1 = std::min(y0 + 1, rgb.rows - 1);
            const float xWeight = sourceX - x0;
            const float yWeight = sourceY - y0;
            const cv::Vec4b& topLeft = rgb.at<cv::Vec4b>(y0, x0);
            const cv::Vec4b& topRight = rgb.at<cv::Vec4b>(y0, x1);
            const cv::Vec4b& bottomLeft = rgb.at<cv::Vec4b>(y1, x0);
            const cv::Vec4b& bottomRight = rgb.at<cv::Vec4b>(y1, x1);
            for (int channel = 0; channel < 4; ++channel) {
                const float top = topLeft[channel] +
                    (topRight[channel] - topLeft[channel]) * xWeight;
                const float bottom = bottomLeft[channel] +
                    (bottomRight[channel] - bottomLeft[channel]) * xWeight;
                output[x][channel] = cv::saturate_cast<unsigned char>(
                    top + (bottom - top) * yWeight);
            }
        }
    }
    return crop;
}

}  // namespace

PPOCRv5::PPOCRv5() : targetSize_(960) {}

bool PPOCRv5::load(const char* detParam, const unsigned char* detModel,
                   const char* recParam, const unsigned char* recModel) {
    clear();

    detector_.opt.num_threads = std::clamp(ncnn::get_big_cpu_count(), 1, 4);
    detector_.opt.use_fp16_packed = true;
    detector_.opt.use_fp16_storage = true;
    detector_.opt.use_fp16_arithmetic = true;

    recognizer_.opt.num_threads = 1;
    recognizer_.opt.use_fp16_packed = true;
    recognizer_.opt.use_fp16_storage = true;
    recognizer_.opt.use_fp16_arithmetic = true;

    if (detector_.load_param_mem(detParam) != 0 || detector_.load_model(detModel) == 0 ||
        recognizer_.load_param_mem(recParam) != 0 || recognizer_.load_model(recModel) == 0) {
        clear();
        return false;
    }
    return true;
}

bool PPOCRv5::loadFromFiles(const char* detParamPath, const char* detModelPath,
                            const char* recParamPath, const char* recModelPath) {
    clear();

    detector_.opt.num_threads = std::clamp(ncnn::get_big_cpu_count(), 1, 4);
    detector_.opt.use_fp16_packed = true;
    detector_.opt.use_fp16_storage = true;
    detector_.opt.use_fp16_arithmetic = true;

    recognizer_.opt.num_threads = 1;
    recognizer_.opt.use_fp16_packed = true;
    recognizer_.opt.use_fp16_storage = true;
    recognizer_.opt.use_fp16_arithmetic = true;

    if (detector_.load_param(detParamPath) != 0 ||
        detector_.load_model(detModelPath) != 0 ||
        recognizer_.load_param(recParamPath) != 0 ||
        recognizer_.load_model(recModelPath) != 0) {
        clear();
        return false;
    }
    return true;
}

void PPOCRv5::clear() {
    detector_.clear();
    recognizer_.clear();
}

void PPOCRv5::setTargetSize(int targetSize) {
    targetSize_ = std::max(320, targetSize);
}

bool PPOCRv5::detect(const cv::Mat& rgb, std::vector<OcrObject>& objects) const {
    if (rgb.empty() || rgb.type() != CV_8UC4) {
        return false;
    }

    const int imageWidth = rgb.cols;
    const int imageHeight = rgb.rows;
    constexpr int kStride = 32;

    int width = imageWidth;
    int height = imageHeight;
    float scale = 1.0f;
    if (std::max(width, height) > targetSize_) {
        scale = static_cast<float>(targetSize_) / std::max(width, height);
        width = std::max(1, static_cast<int>(std::round(width * scale)));
        height = std::max(1, static_cast<int>(std::round(height * scale)));
    }

    ncnn::Mat input = ncnn::Mat::from_pixels_resize(
        rgb.data, ncnn::Mat::PIXEL_RGBA2BGR,
        imageWidth, imageHeight, width, height);
    const int widthPadding = (width + kStride - 1) / kStride * kStride - width;
    const int heightPadding = (height + kStride - 1) / kStride * kStride - height;
    ncnn::Mat padded;
    ncnn::copy_make_border(input, padded,
                           heightPadding / 2, heightPadding - heightPadding / 2,
                           widthPadding / 2, widthPadding - widthPadding / 2,
                           ncnn::BORDER_CONSTANT, 114.0f);

    const float meanValues[3] = {
        0.485f * 255.0f, 0.456f * 255.0f, 0.406f * 255.0f,
    };
    const float normValues[3] = {
        1.0f / 0.229f / 255.0f,
        1.0f / 0.224f / 255.0f,
        1.0f / 0.225f / 255.0f,
    };
    padded.substract_mean_normalize(meanValues, normValues);

    ncnn::Extractor extractor = detector_.create_extractor();
    if (extractor.input("in0", padded) != 0) {
        return false;
    }
    ncnn::Mat output;
    if (extractor.extract("out0", output) != 0 || output.w <= 0 || output.h <= 0) {
        return false;
    }

    const float denormalize[1] = {255.0f};
    output.substract_mean_normalize(nullptr, denormalize);
    cv::Mat probability(output.h, output.w, CV_8UC1);
    output.to_pixels(probability.data, ncnn::Mat::PIXEL_GRAY);

    cv::Mat bitmap;
    cv::threshold(probability, bitmap, 0.3 * 255.0, 255.0, cv::THRESH_BINARY);

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(bitmap, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
    if (contours.size() > 1000) {
        contours.resize(1000);
    }

    constexpr float kBoxThreshold = 0.6f;
    constexpr float kEnlargeRatio = 1.95f;
    const float minSize = 3.0f * scale;
    for (const std::vector<cv::Point>& contour : contours) {
        if (contour.size() <= 2) {
            continue;
        }
        const float score = static_cast<float>(contourScore(probability, contour));
        if (score < kBoxThreshold) {
            continue;
        }

        cv::RotatedRect rectangle = cv::minAreaRect(contour);
        if (std::max(rectangle.size.width, rectangle.size.height) < minSize) {
            continue;
        }

        int orientation = 0;
        if (rectangle.angle >= -30.0f && rectangle.angle <= 30.0f &&
            rectangle.size.height > rectangle.size.width * 2.7f) {
            orientation = 1;
        }
        if ((rectangle.angle <= -60.0f || rectangle.angle >= 60.0f) &&
            rectangle.size.width > rectangle.size.height * 2.7f) {
            orientation = 1;
        }
        if (rectangle.angle < -30.0f) {
            rectangle.angle += 180.0f;
        }
        if (orientation == 0 && rectangle.angle < 30.0f) {
            rectangle.angle += 90.0f;
            std::swap(rectangle.size.width, rectangle.size.height);
        }
        if (orientation == 1 && rectangle.angle >= 60.0f) {
            rectangle.angle -= 90.0f;
            std::swap(rectangle.size.width, rectangle.size.height);
        }

        rectangle.size.height += rectangle.size.width * (kEnlargeRatio - 1.0f);
        rectangle.size.width *= kEnlargeRatio;
        rectangle.center.x = (rectangle.center.x - widthPadding / 2.0f) / scale;
        rectangle.center.y = (rectangle.center.y - heightPadding / 2.0f) / scale;
        rectangle.size.width /= scale;
        rectangle.size.height /= scale;

        OcrObject object;
        object.rrect = rectangle;
        object.orientation = orientation;
        object.detectionScore = score;
        objects.push_back(std::move(object));
    }
    return true;
}

bool PPOCRv5::recognize(const cv::Mat& rgb, OcrObject& object) const {
    cv::Mat crop = rotateCrop(rgb, object);
    if (crop.empty()) {
        return false;
    }

    ncnn::Mat input = ncnn::Mat::from_pixels(
        crop.data, ncnn::Mat::PIXEL_RGBA2BGR, crop.cols, crop.rows);
    const float meanValues[3] = {127.5f, 127.5f, 127.5f};
    const float normValues[3] = {
        1.0f / 127.5f, 1.0f / 127.5f, 1.0f / 127.5f,
    };
    input.substract_mean_normalize(meanValues, normValues);

    ncnn::Extractor extractor = recognizer_.create_extractor();
    if (extractor.input("in0", input) != 0) {
        return false;
    }
    ncnn::Mat output;
    if (extractor.extract("out0", output) != 0 || output.w <= 0 || output.h <= 0) {
        return false;
    }

    std::string text;
    float scoreSum = 0.0f;
    int emitted = 0;
    int lastToken = 0;
    for (int timestep = 0; timestep < output.h; ++timestep) {
        const float* scores = output.row(timestep);
        int token = 0;
        float bestScore = scores[0];
        for (int index = 1; index < output.w; ++index) {
            if (scores[index] > bestScore) {
                bestScore = scores[index];
                token = index;
            }
        }
        if (token == lastToken) {
            continue;
        }
        lastToken = token;
        if (token <= 0 || token - 1 >= character_dict_size) {
            continue;
        }
        text += character_dict[token - 1];
        scoreSum += bestScore;
        ++emitted;
    }

    if (text.empty() || emitted == 0) {
        return false;
    }
    const float tokenScore = scoreSum / emitted;
    if (tokenScore < 0.25f) {
        return false;
    }
    object.text = std::move(text);
    object.tokenScore = tokenScore;
    return true;
}

}  // namespace freshcue
