#ifndef FRESHCUE_OFFLINE_OCR_H
#define FRESHCUE_OFFLINE_OCR_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace freshcue {

struct OcrBlock {
    std::string text;
    float left;
    float top;
    float right;
    float bottom;
};

bool loadOfflineModels(const uint8_t* detParam, size_t detParamSize,
                       const uint8_t* detModel, size_t detModelSize,
                       const uint8_t* recParam, size_t recParamSize,
                       const uint8_t* recModel, size_t recModelSize);
bool offlineModelReady();
std::vector<OcrBlock> recognizeOffline(const uint8_t* rgba, int width, int height);

}  // namespace freshcue

#endif
