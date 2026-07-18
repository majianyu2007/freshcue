#include <algorithm>
#include <fstream>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>

#include "offline_ocr.h"

namespace {

struct SmokeCase {
    std::string name;
    cv::Mat image;
    std::vector<std::string> expected;
};

std::vector<uint8_t> readFile(const std::string& path) {
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        return {};
    }
    const std::streamsize size = stream.tellg();
    if (size <= 0) {
        return {};
    }
    std::vector<uint8_t> bytes(static_cast<size_t>(size));
    stream.seekg(0);
    stream.read(reinterpret_cast<char*>(bytes.data()), size);
    return stream ? bytes : std::vector<uint8_t>{};
}

void text(cv::Mat& image, const std::string& value, cv::Point origin,
          double scale, cv::Scalar color, int thickness = 2) {
    cv::putText(image, value, origin, cv::FONT_HERSHEY_DUPLEX,
                scale, color, thickness, cv::LINE_AA);
}

cv::Mat canvas(int width, int height, cv::Scalar color) {
    return cv::Mat(height, width, CV_8UC4, color);
}

std::vector<SmokeCase> cases() {
    std::vector<SmokeCase> result;

    cv::Mat notification = canvas(1080, 520, cv::Scalar(250, 250, 250, 255));
    cv::rectangle(notification, cv::Rect(0, 0, 1080, 84), cv::Scalar(35, 95, 220, 255), -1);
    text(notification, "Calendar notification", {54, 60}, 1.15, {255, 255, 255, 255}, 2);
    text(notification, "Project review", {70, 210}, 1.65, {25, 25, 25, 255}, 3);
    text(notification, "2026-07-25 14:00", {70, 330}, 1.55, {25, 25, 25, 255}, 3);
    result.push_back({"white_notification", notification, {"14:00"}});

    cv::Mat darkChat = canvas(1080, 900, cv::Scalar(24, 27, 32, 255));
    cv::rectangle(darkChat, cv::Rect(70, 220, 870, 260), cv::Scalar(55, 62, 72, 255), -1);
    text(darkChat, "Please send the final draft", {110, 320}, 1.3, {245, 245, 245, 255}, 2);
    text(darkChat, "before 07/28 18:30", {110, 410}, 1.4, {245, 245, 245, 255}, 3);
    result.push_back({"dark_chat", darkChat, {"18:30"}});

    cv::Mat bubbles = canvas(1080, 900, cv::Scalar(238, 240, 244, 255));
    cv::rectangle(bubbles, cv::Rect(250, 170, 760, 230), cv::Scalar(167, 232, 174, 255), -1);
    text(bubbles, "Pickup code expires", {300, 270}, 1.25, {20, 35, 25, 255}, 2);
    text(bubbles, "7/22 20:15", {300, 350}, 1.45, {20, 35, 25, 255}, 3);
    result.push_back({"chat_bubble", bubbles, {"20:15"}});

    cv::Mat mixed = canvas(1200, 920, cv::Scalar(74, 105, 136, 255));
    for (int index = 0; index < 8; ++index) {
        cv::circle(mixed, {110 + index * 145, 170 + (index % 3) * 115},
                   90, cv::Scalar(45 + index * 18, 125, 205 - index * 12, 255), -1);
    }
    cv::rectangle(mixed, cv::Rect(100, 590, 1000, 220), cv::Scalar(250, 250, 247, 255), -1);
    text(mixed, "Train departs 08/03 09:45", {150, 720}, 1.55, {20, 20, 20, 255}, 3);
    result.push_back({"image_text_mix", mixed, {"09:45"}});

    cv::Mat small = canvas(1080, 1920, cv::Scalar(255, 255, 255, 255));
    for (int row = 0; row < 24; ++row) {
        text(small, "message item and details", {45, 90 + row * 70},
             0.52, {70, 70, 70, 255}, 1);
    }
    text(small, "Submit 7/24 23:59", {45, 1780}, 0.58, {25, 25, 25, 255}, 1);
    result.push_back({"small_text", small, {"23:59"}});

    cv::Mat columns = canvas(1200, 900, cv::Scalar(252, 252, 252, 255));
    cv::line(columns, {600, 100}, {600, 800}, cv::Scalar(210, 210, 210, 255), 2);
    text(columns, "Class", {70, 260}, 1.35, {20, 20, 20, 255}, 3);
    text(columns, "7/26 10:00", {70, 350}, 1.35, {20, 20, 20, 255}, 3);
    text(columns, "Exam", {660, 260}, 1.35, {20, 20, 20, 255}, 3);
    text(columns, "7/27 15:30", {660, 350}, 1.35, {20, 20, 20, 255}, 3);
    result.push_back({"two_columns", columns, {"10:00", "15:30"}});

    cv::Mat lowContrast = canvas(1080, 700, cv::Scalar(195, 195, 195, 255));
    text(lowContrast, "Community event", {80, 270}, 1.5, {145, 145, 145, 255}, 3);
    text(lowContrast, "7/29 16:00", {80, 390}, 1.55, {145, 145, 145, 255}, 3);
    result.push_back({"low_contrast", lowContrast, {"16:00"}});

    cv::Mat longShot = canvas(720, 3200, cv::Scalar(248, 248, 248, 255));
    for (int row = 0; row < 30; ++row) {
        cv::rectangle(longShot, cv::Rect(28, 35 + row * 100, 664, 72),
                      row % 2 == 0 ? cv::Scalar(235, 240, 248, 255)
                                   : cv::Scalar(245, 235, 230, 255), -1);
        text(longShot, "conversation history", {55, 82 + row * 100},
             0.65, {65, 65, 65, 255}, 1);
    }
    cv::rectangle(longShot, cv::Rect(28, 2800, 664, 130), cv::Scalar(255, 255, 255, 255), -1);
    text(longShot, "Flight 09/01 08:00", {55, 2880}, 1.05, {15, 15, 15, 255}, 2);
    result.push_back({"long_screenshot", longShot, {"08:00"}});

    cv::Mat ticket = canvas(1400, 760, cv::Scalar(224, 238, 250, 255));
    cv::rectangle(ticket, cv::Rect(90, 100, 1220, 560), cv::Scalar(255, 255, 255, 255), -1);
    cv::line(ticket, {760, 130}, {760, 630}, cv::Scalar(175, 175, 175, 255), 2);
    text(ticket, "BOARDING", {150, 240}, 1.7, {25, 25, 25, 255}, 3);
    text(ticket, "Gate closes", {150, 380}, 1.2, {60, 60, 60, 255}, 2);
    text(ticket, "08/08 06:40", {150, 500}, 1.65, {15, 15, 15, 255}, 3);
    result.push_back({"ticket_layout", ticket, {"06:40"}});

    cv::Mat dense = canvas(1080, 1600, cv::Scalar(250, 248, 242, 255));
    for (int row = 0; row < 14; ++row) {
        text(dense, "Agenda item", {45, 90 + row * 100}, 0.85,
             {40, 40, 40, 255}, 2);
        text(dense, row == 8 ? "07/31 21:20" : "notes and status",
             {500, 90 + row * 100}, 0.85, {40, 40, 40, 255}, 2);
    }
    result.push_back({"dense_list", dense, {"21:20"}});

    return result;
}

std::string normalized(std::string value) {
    value.erase(std::remove_if(value.begin(), value.end(), [](unsigned char character) {
        return character == ' ' || character == '\n' || character == '\r' || character == '\t';
    }), value.end());
    return value;
}

}  // namespace

int main(int argc, char** argv) {
    const std::string modelDirectory = argc > 1
        ? argv[1]
        : "ohos/entry/src/main/resources/rawfile/ocr";
    const std::vector<uint8_t> detParam = readFile(modelDirectory + "/PP_OCRv5_mobile_det.ncnn.param");
    const std::vector<uint8_t> detModel = readFile(modelDirectory + "/PP_OCRv5_mobile_det.ncnn.bin");
    const std::vector<uint8_t> recParam = readFile(modelDirectory + "/PP_OCRv5_mobile_rec.ncnn.param");
    const std::vector<uint8_t> recModel = readFile(modelDirectory + "/PP_OCRv5_mobile_rec.ncnn.bin");
    if (!freshcue::loadOfflineModels(
            detParam.data(), detParam.size(), detModel.data(), detModel.size(),
            recParam.data(), recParam.size(), recModel.data(), recModel.size())) {
        std::cerr << "FAIL model_load\n";
        return 2;
    }

    int passed = 0;
    const std::vector<SmokeCase> smokeCases = cases();
    for (const SmokeCase& smoke : smokeCases) {
        const std::vector<freshcue::OcrBlock> blocks = freshcue::recognizeOffline(
            smoke.image.data, smoke.image.cols, smoke.image.rows);
        std::string fullText;
        for (const freshcue::OcrBlock& block : blocks) {
            if (!fullText.empty()) {
                fullText += '\n';
            }
            fullText += block.text;
        }
        const std::string searchable = normalized(fullText);
        bool success = true;
        for (const std::string& expected : smoke.expected) {
            if (searchable.find(normalized(expected)) == std::string::npos) {
                success = false;
            }
        }
        passed += success ? 1 : 0;
        std::cout << (success ? "PASS " : "FAIL ") << smoke.name
                  << " blocks=" << blocks.size() << " text=" << fullText << '\n';
    }

    std::cout << "RESULT " << passed << "/" << smokeCases.size() << '\n';
    return passed >= 8 ? 0 : 1;
}
