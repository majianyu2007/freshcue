export interface OfflineOcrBlock {
  text: string;
  left: number;
  top: number;
  right: number;
  bottom: number;
  lineIndex: number;
}

export const loadModel: (
  detParam: ArrayBuffer,
  detModel: ArrayBuffer,
  recParam: ArrayBuffer,
  recModel: ArrayBuffer,
) => boolean;
export const isReady: () => boolean;
export const recognize: (
  rgbaPixels: ArrayBuffer,
  width: number,
  height: number,
) => Promise<Array<OfflineOcrBlock>>;
