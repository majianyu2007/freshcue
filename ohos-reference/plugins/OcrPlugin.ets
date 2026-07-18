// ⚠️ 参考实现，未真机验证（见 ohos/README.md）。
// channel: freshcue/ocr —— 桥接 Core Vision 通用文字识别。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-text-recognition

import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import {
  MethodCall, MethodChannel, MethodResult, FlutterEngine,
} from '@ohos/flutter_ohos';

export class OcrPlugin {
  private channel: MethodChannel | null = null;

  register(engine: FlutterEngine): void {
    this.channel = new MethodChannel(
      engine.dartExecutor.getBinaryMessenger(), 'freshcue/ocr');
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.onCall(call, result);
      },
    });
  }

  private async onCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'isAvailable': {
        // Core Vision 在支持设备上默认可用；以能力查询/异常为准。
        result.success(canIUse('SystemCapability.AI.Vision.TextRecognition'));
        break;
      }
      case 'recognizeImage': {
        try {
          const uri = call.argument('uri') as string;
          const start = Date.now();
          const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          const source = image.createImageSource(file.fd);
          const pixelMap = await source.createPixelMap();
          const info = await pixelMap.getImageInfo();
          const w = info.size.width;
          const h = info.size.height;

          const request: textRecognition.VisionInfo = { pixelMap: pixelMap };
          const data = await textRecognition.recognizeText(request);

          const blocks: Array<Record<string, Object>> = [];
          let lineIndex = 0;
          for (const block of data.blocks) {
            for (const line of block.lines) {
              const r = line.itemRect; // 像素坐标 → 归一化 0~1
              blocks.push({
                'text': line.value,
                'confidence': 0.9, // API 未提供逐行置信度时的保守值
                'left': r.left / w,
                'top': r.top / h,
                'right': (r.left + r.width) / w,
                'bottom': (r.top + r.height) / h,
                'lineIndex': lineIndex++,
              });
            }
          }
          pixelMap.release();
          source.release();
          fs.closeSync(file);

          result.success({
            'requestId': util.generateRandomUUID(),
            'imageWidth': w,
            'imageHeight': h,
            'fullText': data.value,
            'blocks': blocks,
            'engine': 'core_vision',
            'durationMs': Date.now() - start,
          });
        } catch (e) {
          // 统一映射为稳定错误码（Flutter 侧 _mapPlatformError 消费）。
          result.error('ocr_failed', `${(e as Error).name}`, null);
        }
        break;
      }
      default:
        result.notImplemented();
    }
  }
}
