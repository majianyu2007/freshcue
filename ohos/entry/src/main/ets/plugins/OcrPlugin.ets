// Core Vision 通用文字识别桥接。channel: freshcue/ocr
// API 依据本机 HarmonyOS SDK (API 24) 的 @hms.ai.ocr.textRecognition：
//   recognizeText(VisionInfo, config?): Promise<TextRecognitionResult>
//   结果 blocks[].lines[] 含 value + cornerPoints(多边形)，无逐行 confidence。
// 文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-text-recognition
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';
import { CapabilityRegistry } from './CapabilitiesPlugin';

export class OcrPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'OcrPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/ocr');
    this.channel.setMethodCallHandler(this);
    // 编译接入即 compiled=true；available 由 syscap 决定。
    const available = canIUse('SystemCapability.AI.OCR.TextRecognition');
    CapabilityRegistry.mark('ocr', true, available,
      available ? '' : 'device_unsupported');
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isAvailable':
        result.success(canIUse('SystemCapability.AI.OCR.TextRecognition'));
        break;
      case 'recognizeImage':
        this.recognize(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  private async recognize(call: MethodCall, result: MethodResult): Promise<void> {
    const uri = call.argument('uri') as string;
    if (uri === null || uri.length === 0) {
      result.error('invalid_image', 'empty uri', null);
      return;
    }
    const start = Date.now();
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let inited = false;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      pixelMap = await source.createPixelMap();
      const info = await pixelMap.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;

      await textRecognition.init();
      inited = true;
      const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
      const data = await textRecognition.recognizeText(visionInfo,
        { isDirectionDetectionSupported: true });

      const blocks: Array<Record<string, Object>> = [];
      let lineIndex = 0;
      for (const block of data.blocks) {
        for (const line of block.lines) {
          const box = OcrPlugin.boundingBox(line.cornerPoints, w, h);
          // 无逐行 confidence → 不写该字段，Flutter 侧读为 null。
          blocks.push({
            'text': line.value,
            'left': box[0],
            'top': box[1],
            'right': box[2],
            'bottom': box[3],
            'lineIndex': lineIndex,
          });
          lineIndex++;
        }
      }

      const payload: Record<string, Object> = {
        'requestId': util.generateRandomUUID(),
        'imageWidth': w,
        'imageHeight': h,
        'fullText': data.value,
        'blocks': blocks,
        'engine': 'core_vision',
        'durationMs': Date.now() - start,
      };
      result.success(payload);
    } catch (e) {
      const err = e as BusinessError;
      result.error('ocr_failed', `code=${err.code}`, null);
    } finally {
      if (inited) {
        try { await textRecognition.release(); } catch (_e) { /* ignore */ }
      }
      pixelMap?.release();
      source?.release();
      if (file !== null) {
        try { fs.closeSync(file); } catch (_e) { /* ignore */ }
      }
    }
  }

  /// 多边形角点 → 归一化包围盒 [left, top, right, bottom]（0~1）。
  private static boundingBox(
    points: Array<textRecognition.PixelPoint>, w: number, h: number,
  ): Array<number> {
    if (points.length === 0 || w === 0 || h === 0) {
      return [0, 0, 0, 0];
    }
    let minX = points[0].x;
    let maxX = points[0].x;
    let minY = points[0].y;
    let maxY = points[0].y;
    for (const p of points) {
      if (p.x < minX) { minX = p.x; }
      if (p.x > maxX) { maxX = p.x; }
      if (p.y < minY) { minY = p.y; }
      if (p.y > maxY) { maxY = p.y; }
    }
    return [minX / w, minY / h, maxX / w, maxY / h];
  }
}
