// FreshCue offline OCR provider.
// PP-OCRv5 recognition model conversion and character dictionary are derived
// from nihui/ncnn-android-ppocrv5 (BSD-3-Clause). The model originates from
// PaddleOCR (Apache-2.0). See the packaged THIRD_PARTY_NOTICES.txt.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "cpu.h"
#include "net.h"
#include "offline_ocr.h"
#include "ppocrv5_dict.h"

namespace freshcue {


namespace {

struct Crop {
    int left;
    int top;
    int right;
    int bottom;
};

ncnn::Net g_recognizer;
std::vector<unsigned char> g_param;
std::vector<unsigned char> g_model;
std::mutex g_mutex;
bool g_ready = false;

inline uint8_t luminance(const uint8_t* pixel) {
    return static_cast<uint8_t>((77 * pixel[0] + 150 * pixel[1] + 29 * pixel[2]) >> 8);
}

uint8_t estimateBackground(const uint8_t* rgba, int width, int height) {
    std::vector<uint8_t> samples;
    const int stepX = std::max(1, width / 64);
    const int stepY = std::max(1, height / 64);
    samples.reserve(256);
    for (int x = 0; x < width; x += stepX) {
        samples.push_back(luminance(rgba + static_cast<size_t>(x) * 4));
        samples.push_back(luminance(rgba + (static_cast<size_t>(height - 1) * width + x) * 4));
    }
    for (int y = 0; y < height; y += stepY) {
        samples.push_back(luminance(rgba + static_cast<size_t>(y) * width * 4));
        samples.push_back(luminance(rgba + (static_cast<size_t>(y) * width + width - 1) * 4));
    }
    const auto middle = samples.begin() + samples.size() / 2;
    std::nth_element(samples.begin(), middle, samples.end());
    return *middle;
}

std::vector<Crop> detectTextLines(const uint8_t* rgba, int width, int height) {
    const uint8_t background = estimateBackground(rgba, width, height);
    constexpr int kContrast = 32;
    const int minRowInk = std::max(2, width / 300);
    const int joinGap = std::max(2, height / 800);
    const int minHeight = std::max(6, height / 500);

    std::vector<uint8_t> gray(static_cast<size_t>(width) * height);
    std::vector<int> rowInk(height, 0);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const size_t index = static_cast<size_t>(y) * width + x;
            const uint8_t value = luminance(rgba + index * 4);
            gray[index] = value;
            if (std::abs(static_cast<int>(value) - background) >= kContrast) {
                ++rowInk[y];
            }
        }
    }

    std::vector<std::pair<int, int>> bands;
    int start = -1;
    int lastActive = -1;
    for (int y = 0; y < height; ++y) {
        if (rowInk[y] >= minRowInk) {
            if (start < 0) {
                start = y;
            }
            lastActive = y;
        } else if (start >= 0 && y - lastActive > joinGap) {
            if (lastActive - start + 1 >= minHeight) {
                bands.emplace_back(start, lastActive);
            }
            start = -1;
            lastActive = -1;
        }
    }
    if (start >= 0 && lastActive - start + 1 >= minHeight) {
        bands.emplace_back(start, lastActive);
    }

    std::vector<Crop> crops;
    crops.reserve(bands.size());
    for (const auto& band : bands) {
        const int bandHeight = band.second - band.first + 1;
        const int minColInk = std::max(1, bandHeight / 8);
        int left = width;
        int right = -1;
        for (int x = 0; x < width; ++x) {
            int ink = 0;
            for (int y = band.first; y <= band.second; ++y) {
                const uint8_t value = gray[static_cast<size_t>(y) * width + x];
                if (std::abs(static_cast<int>(value) - background) >= kContrast) {
                    ++ink;
                }
            }
            if (ink >= minColInk) {
                left = std::min(left, x);
                right = std::max(right, x);
            }
        }
        if (right < left || right - left + 1 < bandHeight / 2) {
            continue;
        }
        const int xPad = std::max(2, bandHeight / 4);
        const int yPad = std::max(2, bandHeight / 6);
        crops.push_back({
            std::max(0, left - xPad),
            std::max(0, band.first - yPad),
            std::min(width, right + xPad + 1),
            std::min(height, band.second + yPad + 1),
        });
    }
    return crops;
}

bool recognizeCrop(const uint8_t* rgba, int imageWidth, const Crop& crop, OcrBlock& result) {
    const int cropWidth = crop.right - crop.left;
    const int cropHeight = crop.bottom - crop.top;
    if (cropWidth <= 0 || cropHeight <= 0) {
        return false;
    }

    std::vector<uint8_t> rgb(static_cast<size_t>(cropWidth) * cropHeight * 3);
    for (int y = 0; y < cropHeight; ++y) {
        const uint8_t* source = rgba +
            (static_cast<size_t>(crop.top + y) * imageWidth + crop.left) * 4;
        uint8_t* destination = rgb.data() + static_cast<size_t>(y) * cropWidth * 3;
        for (int x = 0; x < cropWidth; ++x) {
            destination[x * 3] = source[x * 4];
            destination[x * 3 + 1] = source[x * 4 + 1];
            destination[x * 3 + 2] = source[x * 4 + 2];
        }
    }

    constexpr int targetHeight = 48;
    const int targetWidth = std::clamp(
        static_cast<int>(std::round(static_cast<double>(cropWidth) * targetHeight / cropHeight)),
        targetHeight,
        1280);
    ncnn::Mat input = ncnn::Mat::from_pixels_resize(
        rgb.data(), ncnn::Mat::PIXEL_RGB2BGR,
        cropWidth, cropHeight, targetWidth, targetHeight);
    const float meanValues[3] = {127.5f, 127.5f, 127.5f};
    const float normValues[3] = {1.0f / 127.5f, 1.0f / 127.5f, 1.0f / 127.5f};
    input.substract_mean_normalize(meanValues, normValues);

    ncnn::Extractor extractor = g_recognizer.create_extractor();
    if (extractor.input("in0", input) != 0) {
        return false;
    }
    ncnn::Mat output;
    if (extractor.extract("out0", output) != 0 || output.w <= 0 || output.h <= 0) {
        return false;
    }

    std::string text;
    float confidenceSum = 0.0f;
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
        confidenceSum += bestScore;
        ++emitted;
    }

    if (text.empty() || emitted == 0) {
        return false;
    }
    const float confidence = confidenceSum / emitted;
    if (confidence < 0.25f) {
        return false;
    }
    result.text = std::move(text);
    result.confidence = confidence;
    return true;
}

}  // namespace

bool loadOfflineModel(const uint8_t* param, size_t paramSize,
                      const uint8_t* model, size_t modelSize) {
    if (param == nullptr || model == nullptr || paramSize == 0 || modelSize == 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_ready) {
        return true;
    }
    g_param.assign(param, param + paramSize);
    g_param.push_back(0);
    g_model.assign(model, model + modelSize);

    g_recognizer.opt.num_threads = std::clamp(ncnn::get_big_cpu_count(), 1, 4);
    g_recognizer.opt.use_fp16_packed = true;
    g_recognizer.opt.use_fp16_storage = true;
    g_recognizer.opt.use_fp16_arithmetic = true;
    if (g_recognizer.load_param_mem(reinterpret_cast<const char*>(g_param.data())) != 0 ||
        g_recognizer.load_model(g_model.data()) == 0) {
        g_recognizer.clear();
        g_param.clear();
        g_model.clear();
        return false;
    }
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

    const std::vector<Crop> crops = detectTextLines(rgba, width, height);
    std::vector<OcrBlock> blocks;
    blocks.reserve(crops.size());
    for (const Crop& crop : crops) {
        OcrBlock block{};
        if (!recognizeCrop(rgba, width, crop, block)) {
            continue;
        }
        block.left = static_cast<float>(crop.left) / width;
        block.top = static_cast<float>(crop.top) / height;
        block.right = static_cast<float>(crop.right) / width;
        block.bottom = static_cast<float>(crop.bottom) / height;
        blocks.push_back(std::move(block));
    }
    return blocks;
}

}  // namespace freshcue
