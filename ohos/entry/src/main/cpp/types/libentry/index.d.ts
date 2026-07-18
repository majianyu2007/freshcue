export interface OfflineOcrBlock {
  text: string;
  confidence: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
  lineIndex: number;
}

export const loadModel: (param: ArrayBuffer, model: ArrayBuffer) => boolean;
export const isReady: () => boolean;
export const recognize: (
  rgbaPixels: ArrayBuffer,
  width: number,
  height: number,
) => Promise<Array<OfflineOcrBlock>>;
