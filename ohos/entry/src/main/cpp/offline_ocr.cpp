// FreshCue offline OCR provider.
// PP-OCRv5 detector/recognizer models and postprocessing are derived from
// nihui/ncnn-android-ppocrv5 (BSD-3-Clause); models originate from PaddleOCR
// (Apache-2.0). See the packaged THIRD_PARTY_NOTICES.txt.

#include "offline_ocr.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <numeric>
#include <utility>
#include <vector>

#include <opencv2/core/core.hpp>

#include "ppocrv5.h"

namespace freshcue {
namespace {

constexpr int kTileSize = 1280;
constexpr int kTileOverlap = 192;
constexpr size_t kMaxDetectedRegions = 512;

PPOCRv5 g_engine;
std::vector<unsigned char> g_detParam;
std::vector<unsigned char> g_detModel;
std::vector<unsigned char> g_recParam;
std::vector<unsigned char> g_recModel;
std::mutex g_mutex;
bool g_ready = false;

std::vector<int> tileStarts(int length) {
    if (length <= kTileSize) {
        return {0};
    }
    const int stride = kTileSize - kTileOverlap;
    std::vector<int> starts;
    for (int start = 0; start + kTileSize < length; start += stride) {
        starts.push_back(start);
    }
    const int finalStart = length - kTileSize;
    if (starts.empty() || starts.back() != finalStart) {
        starts.push_back(finalStart);
    }
    return starts;
}

cv::Rect2f clippedBounds(const OcrObject& object, int width, int height) {
    return object.rrect.boundingRect2f() &
        cv::Rect2f(0.0f, 0.0f, static_cast<float>(width), static_cast<float>(height));
}

float intersectionOverUnion(const cv::Rect2f& first, const cv::Rect2f& second) {
    const cv::Rect2f intersection = first & second;
    if (intersection.empty()) {
        return 0.0f;
    }
    const float unionArea = first.area() + second.area() - intersection.area();
    return unionArea <= 0.0f ? 0.0f : intersection.area() / unionArea;
}

void appendUnique(std::vector<OcrObject>& objects, OcrObject candidate,
                  int width, int height) {
    const cv::Rect2f candidateBounds = clippedBounds(candidate, width, height);
    if (candidateBounds.width < 2.0f || candidateBounds.height < 2.0f) {
        return;
    }
    for (OcrObject& existing : objects) {
        if (intersectionOverUnion(candidateBounds, clippedBounds(existing, width, height)) < 0.35f) {
            continue;
        }
        if (candidate.detectionScore > existing.detectionScore) {
            existing = std::move(candidate);
        }
        return;
    }
    if (objects.size() < kMaxDetectedRegions) {
        objects.push_back(std::move(candidate));
    }
}

void detectTiles(const cv::Mat& rgba, std::vector<OcrObject>& objects) {
    const std::vector<int> xStarts = tileStarts(rgba.cols);
    const std::vector<int> yStarts = tileStarts(rgba.rows);
    for (int top : yStarts) {
        for (int left : xStarts) {
            const int tileWidth = std::min(kTileSize, rgba.cols - left);
            const int tileHeight = std::min(kTileSize, rgba.rows - top);
            const cv::Mat tile = rgba(cv::Rect(left, top, tileWidth, tileHeight));
            std::vector<OcrObject> detected;
            if (!g_engine.detect(tile, detected)) {
                continue;
            }
            for (OcrObject& object : detected) {
                object.rrect.center.x += left;
                object.rrect.center.y += top;
                appendUnique(objects, std::move(object), rgba.cols, rgba.rows);
            }
        }
    }
}

std::vector<OcrObject> sortReadingOrder(std::vector<OcrObject> objects) {
    std::stable_sort(objects.begin(), objects.end(), [](const OcrObject& first,
                                                        const OcrObject& second) {
        return first.rrect.center.y < second.rrect.center.y;
    });

    struct Row {
        float centerY;
        float textHeight;
        std::vector<OcrObject> objects;
    };
    std::vector<Row> rows;
    for (OcrObject& object : objects) {
        const float textHeight = std::max(1.0f, object.rrect.size.width);
        Row* nearest = nullptr;
        float nearestDistance = 0.0f;
        for (Row& row : rows) {
            const float distance = std::abs(object.rrect.center.y - row.centerY);
            const float tolerance = std::max(10.0f, 0.6f * std::max(textHeight, row.textHeight));
            if (distance <= tolerance && (nearest == nullptr || distance < nearestDistance)) {
                nearest = &row;
                nearestDistance = distance;
            }
        }
        if (nearest == nullptr) {
            rows.push_back({object.rrect.center.y, textHeight, {std::move(object)}});
            continue;
        }
        const float count = static_cast<float>(nearest->objects.size());
        nearest->centerY = (nearest->centerY * count + object.rrect.center.y) / (count + 1.0f);
        nearest->textHeight = std::max(nearest->textHeight, textHeight);
        nearest->objects.push_back(std::move(object));
    }

    std::sort(rows.begin(), rows.end(), [](const Row& first, const Row& second) {
        return first.centerY < second.centerY;
    });
    std::vector<OcrObject> ordered;
    ordered.reserve(objects.size());
    for (Row& row : rows) {
        std::sort(row.objects.begin(), row.objects.end(), [](const OcrObject& first,
                                                            const OcrObject& second) {
            return first.rrect.center.x < second.rrect.center.x;
        });
        for (OcrObject& object : row.objects) {
            ordered.push_back(std::move(object));
        }
    }
    return ordered;
}

void clearModels() {
    g_engine.clear();
    g_detParam.clear();
    g_detModel.clear();
    g_recParam.clear();
    g_recModel.clear();
    g_ready = false;
}

}  // namespace

bool loadOfflineModels(const uint8_t* detParam, size_t detParamSize,
                       const uint8_t* detModel, size_t detModelSize,
                       const uint8_t* recParam, size_t recParamSize,
                       const uint8_t* recModel, size_t recModelSize) {
    if (detParam == nullptr || detModel == nullptr || recParam == nullptr || recModel == nullptr ||
        detParamSize == 0 || detModelSize == 0 || recParamSize == 0 || recModelSize == 0) {
        return false;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_ready) {
        return true;
    }

    g_detParam.assign(detParam, detParam + detParamSize);
    g_detParam.push_back(0);
    g_detModel.assign(detModel, detModel + detModelSize);
    g_recParam.assign(recParam, recParam + recParamSize);
    g_recParam.push_back(0);
    g_recModel.assign(recModel, recModel + recModelSize);

    if (!g_engine.load(reinterpret_cast<const char*>(g_detParam.data()), g_detModel.data(),
                       reinterpret_cast<const char*>(g_recParam.data()), g_recModel.data())) {
        clearModels();
        return false;
    }
    g_engine.setTargetSize(960);
    g_ready = true;
    return true;
}

bool offlineModelReady() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_ready;
}

std::vector<OcrBlock> recognizeOffline(const uint8_t* rgba, int width, int height) {
    if (rgba == nullptr || width <= 0 || height <= 0) {
        return {};
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_ready) {
        return {};
    }

    const cv::Mat image(height, width, CV_8UC4, const_cast<uint8_t*>(rgba));
    std::vector<OcrObject> detected;
    detectTiles(image, detected);
    std::vector<OcrObject> ordered = sortReadingOrder(std::move(detected));

    std::vector<OcrBlock> blocks;
    blocks.reserve(ordered.size());
    for (OcrObject& object : ordered) {
        if (!g_engine.recognize(image, object)) {
            continue;
        }
        const cv::Rect2f bounds = clippedBounds(object, width, height);
        if (bounds.empty()) {
            continue;
        }
        blocks.push_back({
            std::move(object.text),
            bounds.x / width,
            bounds.y / height,
            (bounds.x + bounds.width) / width,
            (bounds.y + bounds.height) / height,
        });
    }
    return blocks;
}

}  // namespace freshcue
