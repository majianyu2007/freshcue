#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "napi/native_api.h"
#include "offline_ocr.h"

namespace {

bool getArrayBuffer(napi_env env, napi_value value, uint8_t*& data, size_t& size) {
    void* raw = nullptr;
    if (napi_get_arraybuffer_info(env, value, &raw, &size) != napi_ok || raw == nullptr) {
        return false;
    }
    data = static_cast<uint8_t*>(raw);
    return true;
}

napi_value booleanValue(napi_env env, bool value) {
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value LoadModel(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc != 4) {
        return booleanValue(env, false);
    }
    uint8_t* detParam = nullptr;
    uint8_t* detModel = nullptr;
    uint8_t* recParam = nullptr;
    uint8_t* recModel = nullptr;
    size_t detParamSize = 0;
    size_t detModelSize = 0;
    size_t recParamSize = 0;
    size_t recModelSize = 0;
    if (!getArrayBuffer(env, argv[0], detParam, detParamSize) ||
        !getArrayBuffer(env, argv[1], detModel, detModelSize) ||
        !getArrayBuffer(env, argv[2], recParam, recParamSize) ||
        !getArrayBuffer(env, argv[3], recModel, recModelSize)) {
        return booleanValue(env, false);
    }
    return booleanValue(env, freshcue::loadOfflineModels(
        detParam, detParamSize, detModel, detModelSize,
        recParam, recParamSize, recModel, recModelSize));
}

napi_value IsReady(napi_env env, napi_callback_info) {
    return booleanValue(env, freshcue::offlineModelReady());
}

struct RecognitionWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref pixelsRef = nullptr;
    const uint8_t* pixels = nullptr;
    int width = 0;
    int height = 0;
    std::vector<freshcue::OcrBlock> blocks;
    std::string error;
};

void ExecuteRecognition(napi_env, void* raw) {
    RecognitionWork* work = static_cast<RecognitionWork*>(raw);
    if (!freshcue::offlineModelReady()) {
        work->error = "model_not_ready";
        return;
    }
    work->blocks = freshcue::recognizeOffline(work->pixels, work->width, work->height);
}

void setNamedString(napi_env env, napi_value object, const char* name, const std::string& value) {
    napi_value property = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &property);
    napi_set_named_property(env, object, name, property);
}

void setNamedDouble(napi_env env, napi_value object, const char* name, double value) {
    napi_value property = nullptr;
    napi_create_double(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void setNamedInt(napi_env env, napi_value object, const char* name, int value) {
    napi_value property = nullptr;
    napi_create_int32(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void CompleteRecognition(napi_env env, napi_status status, void* raw) {
    std::unique_ptr<RecognitionWork> work(static_cast<RecognitionWork*>(raw));
    if (work->pixelsRef != nullptr) {
        napi_delete_reference(env, work->pixelsRef);
        work->pixelsRef = nullptr;
    }
    if (status != napi_ok || !work->error.empty()) {
        napi_value message = nullptr;
        napi_value error = nullptr;
        const std::string text = work->error.empty() ? "recognition_cancelled" : work->error;
        napi_create_string_utf8(env, text.c_str(), text.size(), &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, work->deferred, error);
        napi_delete_async_work(env, work->work);
        return;
    }

    napi_value result = nullptr;
    napi_create_array_with_length(env, work->blocks.size(), &result);
    for (size_t index = 0; index < work->blocks.size(); ++index) {
        const freshcue::OcrBlock& block = work->blocks[index];
        napi_value item = nullptr;
        napi_create_object(env, &item);
        setNamedString(env, item, "text", block.text);
        setNamedDouble(env, item, "left", block.left);
        setNamedDouble(env, item, "top", block.top);
        setNamedDouble(env, item, "right", block.right);
        setNamedDouble(env, item, "bottom", block.bottom);
        setNamedInt(env, item, "lineIndex", static_cast<int>(index));
        napi_set_element(env, result, index, item);
    }
    napi_resolve_deferred(env, work->deferred, result);
    napi_delete_async_work(env, work->work);
}

napi_value Recognize(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);
    if (argc != 3) {
        napi_value message = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, "invalid_arguments", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, deferred, error);
        return promise;
    }

    uint8_t* pixels = nullptr;
    size_t pixelSize = 0;
    int32_t width = 0;
    int32_t height = 0;
    if (!getArrayBuffer(env, argv[0], pixels, pixelSize) ||
        napi_get_value_int32(env, argv[1], &width) != napi_ok ||
        napi_get_value_int32(env, argv[2], &height) != napi_ok ||
        width <= 0 || height <= 0 ||
        pixelSize != static_cast<size_t>(width) * height * 4) {
        napi_value message = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, "invalid_pixel_buffer", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, deferred, error);
        return promise;
    }

    std::unique_ptr<RecognitionWork> work(new RecognitionWork());
    work->env = env;
    work->deferred = deferred;
    work->width = width;
    work->height = height;
    work->pixels = pixels;
    if (napi_create_reference(env, argv[0], 1, &work->pixelsRef) != napi_ok) {
        napi_value message = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, "pixel_reference_failed", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, deferred, error);
        return promise;
    }

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "FreshCueOfflineOcr", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteRecognition,
                               CompleteRecognition, work.get(), &work->work) != napi_ok ||
        napi_queue_async_work(env, work->work) != napi_ok) {
        napi_value message = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, "async_work_failed", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, deferred, error);
        if (work->work != nullptr) {
            napi_delete_async_work(env, work->work);
        }
        napi_delete_reference(env, work->pixelsRef);
        work->pixelsRef = nullptr;
        return promise;
    }
    work.release();
    return promise;
}

napi_value Init(napi_env env, napi_value exports) {
    const napi_property_descriptor properties[] = {
        {"loadModel", nullptr, LoadModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isReady", nullptr, IsReady, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"recognize", nullptr, Recognize, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

napi_module module = {
    1,
    0,
    nullptr,
    Init,
    "entry",
    nullptr,
    {nullptr},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterFreshCueNativeModule() {
    napi_module_register(&module);
}
