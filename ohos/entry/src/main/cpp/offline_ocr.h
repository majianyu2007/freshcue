#ifndef FRESHCUE_OFFLINE_OCR_H
#define FRESHCUE_OFFLINE_OCR_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace freshcue {

struct OcrBlock {
    std::string text;
    float confidence;
    float left;
    float top;
    float right;
    float bottom;
};

bool loadOfflineModel(const uint8_t* param, size_t paramSize,
                      const uint8_t* model, size_t modelSize);
bool offlineModelReady();
std::vector<OcrBlock> recognizeOffline(const uint8_t* rgba, int width, int height);

}  // namespace freshcue

#endif
