export type ZoomFunc = (low: number, high: number) => number[];

export type EncodeBitFunc = (
  low: number,
  high: number,
  mid: number,
  bit: number,
  in_mid_zoom?: number,
) => number[];

export class WebAric {
  private _zoom: ZoomFunc;

  constructor(instance: WebAssembly.Instance) {
    this._zoom = instance.exports._zoom as ZoomFunc;
  }

  zoom(low: number, high: number) {
    return this._zoom(low >>> 0, high >>> 0).map(v => v >>> 0);
  }
}

export async function loadWebAricFromRemote(remotePath: string) {
  const response = await fetch(remotePath);
  const wasm = await WebAssembly.instantiateStreaming(response);
  return new WebAric(wasm.instance);
}

export async function loadWebAric(
  buffer: Buffer,
  loggers: Record<string, (...values: number[]) => void> = {},
) {
  const module = (await WebAssembly.instantiate(buffer, {
    test: {
      zoomStart: () => {},
      zoomEnd: () => {},
      ...loggers,
    },
  })) as any;
  return new WebAric(module.instance);
}
