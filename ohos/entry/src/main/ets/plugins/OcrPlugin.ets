// OCR bridge. Core Vision is preferred. PP-OCRv5 model data is downloaded
// only when the device lacks Core Vision. Channel: freshcue/ocr.
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
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
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

interface ModelFile {
  name: string;
  size: number;
  sha256: string;
}

const MODEL_VERSION = 'ocr-v1';
const RELEASE_ROOT =
  'https://raw.githubusercontent.com/nihui/ncnn-android-ppocrv5/master/app/src/main/assets';
const MODEL_FILES: Array<ModelFile> = [
  {
    name: 'PP_OCRv5_mobile_det.ncnn.param',
    size: 24821,
    sha256: '358f459680ae0e7a73e477469e529ce116f68c629019ec7a0b6457d2d9117934',
  },
  {
    name: 'PP_OCRv5_mobile_det.ncnn.bin',
    size: 2357216,
    sha256: '857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b',
  },
  {
    name: 'PP_OCRv5_mobile_rec.ncnn.param',
    size: 20031,
    sha256: 'f52a6586ac3338d8c350db0c9f3c55ff2ecd3763327f9bc7f0efc091f8a63e74',
  },
  {
    name: 'PP_OCRv5_mobile_rec.ncnn.bin',
    size: 8242276,
    sha256: '49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0',
  },
];

export class OcrPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private offlineLoad: Promise<boolean> | null = null;
  private filesDir: string = '';
  private downloadedBytes: number = 0;
  private downloading: boolean = false;

  getUniqueClassName(): string {
    return 'OcrPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.filesDir = binding.getApplicationContext().filesDir;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'freshcue/ocr');
    this.channel.setMethodCallHandler(this);
    const coreAvailable = canIUse('SystemCapability.AI.OCR.TextRecognition');
    const offlineReady = this.modelsInstalled();
    CapabilityRegistry.mark(
      'ocr',
      true,
      coreAvailable || offlineReady,
      coreAvailable || offlineReady ? '' : 'model_download_required',
      coreAvailable ? 'coreVision' : offlineReady ? 'offline' : 'none',
    );
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.filesDir = '';
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isAvailable':
        this.reportAvailability(result);
        break;
      case 'recognizeImage':
        this.recognize(call, result);
        break;
      case 'getModelStatus':
        result.success(this.modelStatus());
        break;
      case 'downloadModels':
        this.downloadModels(call, result);
        break;
      case 'deleteModels':
        this.deleteModels(result);
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
    if (!this.modelsInstalled()) {
      return false;
    }
    try {
      const paths = MODEL_FILES.map((item: ModelFile): string =>
        `${this.modelDir()}/${item.name}`);
      return offlineOcr.loadModelFiles(paths[0], paths[1], paths[2], paths[3]);
    } catch (_e) {
      return false;
    }
  }

  private modelDir(): string {
    return `${this.filesDir}/ocr/${MODEL_VERSION}`;
  }

  private modelsInstalled(): boolean {
    if (this.filesDir.length === 0) {
      return false;
    }
    try {
      for (const item of MODEL_FILES) {
        const stat = fs.statSync(`${this.modelDir()}/${item.name}`);
        if (stat.size !== item.size) {
          return false;
        }
      }
      return true;
    } catch (_e) {
      return false;
    }
  }

  private modelStatus(): Record<string, Object> {
    const coreVision = canIUse('SystemCapability.AI.OCR.TextRecognition');
    return {
      'coreVisionSupported': coreVision,
      'installed': this.modelsInstalled(),
      'version': MODEL_VERSION,
      'downloadBytes': MODEL_FILES.reduce(
        (sum: number, item: ModelFile): number => sum + item.size, 0),
      'downloadedBytes': this.downloadedBytes,
      'downloading': this.downloading,
      'provider': coreVision ? 'coreVision' :
        this.modelsInstalled() ? 'offline' : 'none',
    };
  }

  private sourceRoot(source: string): string {
    switch (source) {
      case 'ghproxy':
        return `https://ghproxy.net/${RELEASE_ROOT}`;
      case 'fastly':
        return `https://ghfast.top/${RELEASE_ROOT}`;
      default:
        return RELEASE_ROOT;
    }
  }

  private async downloadModels(call: MethodCall, result: MethodResult): Promise<void> {
    const source = call.argument('source') as string;
    const dir = this.modelDir();
    this.downloadedBytes = 0;
    this.downloading = true;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const root = this.sourceRoot(source);
      for (const item of MODEL_FILES) {
        const bytes = await this.download(`${root}/${item.name}`);
        if (bytes.byteLength !== item.size ||
            await OcrPlugin.sha256(bytes) !== item.sha256) {
          throw new Error(`checksum_failed:${item.name}`);
        }
        this.downloadedBytes += bytes.byteLength;
        const temp = `${dir}/${item.name}.download`;
        this.writeFile(temp, bytes);
      }
      for (const item of MODEL_FILES) {
        const target = `${dir}/${item.name}`;
        try { fs.unlinkSync(target); } catch (_e) { /* absent */ }
        fs.renameSync(`${target}.download`, target);
      }
      this.offlineLoad = null;
      const ready = await this.ensureOfflineReady();
      CapabilityRegistry.mark('ocr', true, ready,
        ready ? '' : 'offline_model_failed', ready ? 'offline' : 'none');
      if (!ready) {
        throw new Error('offline_model_failed');
      }
      result.success(this.modelStatus());
    } catch (e) {
      for (const item of MODEL_FILES) {
        try {
          fs.unlinkSync(`${dir}/${item.name}.download`);
        } catch (_e) { /* absent */ }
      }
      const message = e instanceof Error ? e.message : 'download_failed';
      result.error('model_download_failed', message, null);
    } finally {
      this.downloading = false;
    }
  }

  private deleteModels(result: MethodResult): void {
    try {
      offlineOcr.clearModel();
      for (const item of MODEL_FILES) {
        try { fs.unlinkSync(`${this.modelDir()}/${item.name}`); } catch (_e) { /* absent */ }
      }
      this.offlineLoad = null;
      CapabilityRegistry.mark('ocr', true, false, 'model_download_required', 'none');
      result.success(this.modelStatus());
    } catch (_e) {
      result.error('model_delete_failed', 'delete failed', null);
    }
  }

  private async download(url: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 30000,
        readTimeout: 120000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      });
      if (response.responseCode < 200 || response.responseCode >= 300 ||
          !(response.result instanceof ArrayBuffer)) {
        throw new Error(`http_${response.responseCode}`);
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }

  private writeFile(path: string, bytes: ArrayBuffer): void {
    const file = fs.openSync(
      path,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC,
    );
    try {
      fs.writeSync(file.fd, bytes);
    } finally {
      fs.closeSync(file);
    }
  }

  private static async sha256(bytes: ArrayBuffer): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new Uint8Array(bytes) });
    const digest = await md.digest();
    return Array.from(digest.data)
      .map((value: number): string => value.toString(16).padStart(2, '0'))
      .join('');
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
