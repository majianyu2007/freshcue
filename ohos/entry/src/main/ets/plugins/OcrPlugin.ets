// OCR bridge. Core Vision is preferred; bundled PP-OCRv5/ncnn is the
// distributable offline fallback. Channel: freshcue/ocr.
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
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';
import offlineOcr from 'libentry.so';
import { CapabilityRegistry } from './CapabilitiesPlugin';

interface NativeOcrBlock {
  text: string;
  left: number;
  top: number;
  right: number;
  bottom: number;
  lineIndex: number;
}

export class OcrPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private resources: resourceManager.ResourceManager | null = null;
  private offlineLoad: Promise<boolean> | null = null;

  getUniqueClassName(): string {
    return 'OcrPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.resources = binding.getApplicationContext().resourceManager;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/ocr');
    this.channel.setMethodCallHandler(this);
    const coreAvailable = canIUse('SystemCapability.AI.OCR.TextRecognition');
    CapabilityRegistry.mark('ocr', true, true, '', coreAvailable ? 'coreVision' : 'offline');
    if (!coreAvailable) {
      this.ensureOfflineReady().then((ready: boolean) => {
        CapabilityRegistry.mark('ocr', true, ready,
          ready ? '' : 'offline_model_failed', ready ? 'offline' : 'none');
      });
    }
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.resources = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isAvailable':
        this.reportAvailability(result);
        break;
      case 'recognizeImage':
        this.recognize(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  private async reportAvailability(result: MethodResult): Promise<void> {
    if (canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      result.success(true);
      return;
    }
    result.success(await this.ensureOfflineReady());
  }

  private async ensureOfflineReady(): Promise<boolean> {
    if (offlineOcr.isReady()) {
      return true;
    }
    if (this.offlineLoad !== null) {
      return this.offlineLoad;
    }
    this.offlineLoad = this.loadOfflineModel();
    return this.offlineLoad;
  }

  private async loadOfflineModel(): Promise<boolean> {
    if (this.resources === null) {
      return false;
    }
    try {
      const detParam = await this.resources.getRawFileContent(
        'ocr/PP_OCRv5_mobile_det.ncnn.param');
      const detModel = await this.resources.getRawFileContent(
        'ocr/PP_OCRv5_mobile_det.ncnn.bin');
      const recParam = await this.resources.getRawFileContent(
        'ocr/PP_OCRv5_mobile_rec.ncnn.param');
      const recModel = await this.resources.getRawFileContent(
        'ocr/PP_OCRv5_mobile_rec.ncnn.bin');
      return offlineOcr.loadModel(
        detParam.buffer as ArrayBuffer,
        detModel.buffer as ArrayBuffer,
        recParam.buffer as ArrayBuffer,
        recModel.buffer as ArrayBuffer);
    } catch (_e) {
      return false;
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
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const sourceInfo = await source.getImageInfo();
      const decodeSize = OcrPlugin.boundedDecodeSize(
        sourceInfo.size.width, sourceInfo.size.height);
      pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: decodeSize,
      });
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;

      if (canIUse('SystemCapability.AI.OCR.TextRecognition')) {
        try {
          const corePayload = await this.recognizeWithCoreVision(
            pixelMap, width, height, start);
          if ((corePayload['fullText'] as string).trim().length > 0) {
            CapabilityRegistry.mark('ocr', true, true, '', 'coreVision');
            result.success(corePayload);
            return;
          }
        } catch (_coreError) {
          // Continue with the bundled provider. Manual entry remains available
          // in Flutter if both providers fail.
        }
      }

      const offlinePayload = await this.recognizeWithOffline(
        pixelMap, width, height, start);
      CapabilityRegistry.mark('ocr', true, true, '', 'offline');
      result.success(offlinePayload);
    } catch (e) {
      const err = e as BusinessError;
      const detail = err.code === undefined ? 'offline_failed' : `code=${err.code}`;
      CapabilityRegistry.mark('ocr', true, false, 'runtime_failure', 'none');
      result.error('ocr_failed', detail, null);
    } finally {
      pixelMap?.release();
      source?.release();
      if (file !== null) {
        try { fs.closeSync(file); } catch (_e) { /* ignore */ }
      }
    }
  }

  private async recognizeWithCoreVision(
    pixelMap: image.PixelMap,
    width: number,
    height: number,
    start: number,
  ): Promise<Record<string, Object>> {
    let initialized = false;
    try {
      await textRecognition.init();
      initialized = true;
      const data = await textRecognition.recognizeText(
        { pixelMap: pixelMap }, { isDirectionDetectionSupported: true });
      const blocks: Array<Record<string, Object>> = [];
      let lineIndex = 0;
      for (const block of data.blocks) {
        for (const line of block.lines) {
          const box = OcrPlugin.boundingBox(line.cornerPoints, width, height);
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
      return this.payload(width, height, data.value, blocks, 'coreVision', start);
    } finally {
      if (initialized) {
        try { await textRecognition.release(); } catch (_e) { /* ignore */ }
      }
    }
  }

  private async recognizeWithOffline(
    pixelMap: image.PixelMap,
    width: number,
    height: number,
    start: number,
  ): Promise<Record<string, Object>> {
    if (!await this.ensureOfflineReady()) {
      throw new Error('offline_model_failed');
    }
    const pixels = new ArrayBuffer(width * height * 4);
    await pixelMap.readPixelsToBuffer(pixels);
    const nativeBlocks = await offlineOcr.recognize(pixels, width, height) as Array<NativeOcrBlock>;
    if (nativeBlocks.length === 0) {
      throw new Error('offline_no_text');
    }
    const blocks: Array<Record<string, Object>> = nativeBlocks.map(
      (block: NativeOcrBlock): Record<string, Object> => ({
        'text': block.text,
        'left': block.left,
        'top': block.top,
        'right': block.right,
        'bottom': block.bottom,
        'lineIndex': block.lineIndex,
      }));
    const fullText = nativeBlocks.map((block: NativeOcrBlock): string => block.text).join('\n');
    return this.payload(width, height, fullText, blocks, 'offline', start);
  }

  private payload(
    width: number,
    height: number,
    fullText: string,
    blocks: Array<Record<string, Object>>,
    provider: string,
    start: number,
  ): Record<string, Object> {
    return {
      'requestId': util.generateRandomUUID(),
      'imageWidth': width,
      'imageHeight': height,
      'fullText': fullText,
      'blocks': blocks,
      'engine': provider,
      'durationMs': Date.now() - start,
    };
  }

  private static boundedDecodeSize(width: number, height: number): image.Size {
    const maxLongSide = 4096;
    const maxPixels = 6 * 1024 * 1024;
    const scale = Math.min(
      1,
      maxLongSide / Math.max(width, height),
      Math.sqrt(maxPixels / (width * height)),
    );
    return {
      width: Math.max(1, Math.floor(width * scale)),
      height: Math.max(1, Math.floor(height * scale)),
    };
  }

  private static boundingBox(
    points: Array<textRecognition.PixelPoint>, width: number, height: number,
  ): Array<number> {
    if (points.length === 0 || width === 0 || height === 0) {
      return [0, 0, 0, 0];
    }
    let minX = points[0].x;
    let maxX = points[0].x;
    let minY = points[0].y;
    let maxY = points[0].y;
    for (const point of points) {
      minX = Math.min(minX, point.x);
      maxX = Math.max(maxX, point.x);
      minY = Math.min(minY, point.y);
      maxY = Math.max(maxY, point.y);
    }
    return [minX / width, minY / height, maxX / width, maxY / height];
  }
}
