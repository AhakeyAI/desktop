export const SCREEN_WIDTH = 160;
export const SCREEN_HEIGHT = 80;
export type Provider = "minimax" | "glm" | "kimi" | "codex" | "custom";
export type Mapping = { label: string; pointer: string; usedPercent: boolean };
export type Account = {
  id: string;
  label: string;
  provider: Provider;
  international: boolean;
  enabled: boolean;
  warningPercent: number;
  endpoint: string;
  mappings: Mapping[];
};
export type Cards = {
  accounts: Account[];
  autoRefresh: boolean;
  refreshSeconds: number;
};
export type QuotaWindow = {
  id: string;
  label: string;
  remainingPercent: number | null;
  resetsAt: number | null;
  windowMinutes: number | null;
};
export type QuotaResult = {
  accountId: string;
  state: "ready" | "unknown" | "stale" | "error";
  windows: QuotaWindow[];
  checkedAt: number;
  updatedAt: number | null;
  error: string | null;
};
export const providerNames: Record<Provider, string> = {
  minimax: "MiniMax",
  glm: "智谱 GLM",
  kimi: "Kimi Coding",
  codex: "Codex",
  custom: "自定义 HTTP / JSON",
};
export function newAccount(provider: Provider, id: string): Account {
  return {
    id,
    label: providerNames[provider],
    provider,
    international: false,
    enabled: true,
    warningPercent: 20,
    endpoint: "",
    mappings:
      provider === "custom"
        ? [
            {
              label: "剩余额度",
              pointer: "/remainingPercent",
              usedPercent: false,
            },
          ]
        : [],
  };
}
export function defaultCards(): Cards {
  return {
    accounts: (["minimax", "glm", "kimi", "codex"] as Provider[]).map((p) =>
      newAccount(p, p),
    ),
    autoRefresh: false,
    refreshSeconds: 300,
  };
}
export function percentage(value: number | null | undefined): string {
  return value != null && Number.isFinite(value) && value >= 0 && value <= 100
    ? `${Math.round(value)}%`
    : "未知";
}
export function encodeRgb565(
  rgba: Uint8ClampedArray,
  width = SCREEN_WIDTH,
  height = SCREEN_HEIGHT,
): Uint8Array {
  if (
    width !== SCREEN_WIDTH ||
    height !== SCREEN_HEIGHT ||
    rgba.length !== width * height * 4
  )
    throw new Error("图片必须是 160 × 80 RGBA");
  const bytes = new Uint8Array(width * height * 2);
  for (let pixel = 0; pixel < width * height; pixel++) {
    const i = pixel * 4;
    const packed =
      ((rgba[i] >> 3) << 11) | ((rgba[i + 1] >> 2) << 5) | (rgba[i + 2] >> 3);
    bytes[pixel * 2] = packed >> 8;
    bytes[pixel * 2 + 1] = packed & 255;
  }
  return bytes;
}
export function imageDimensions(
  bytes: Uint8Array,
  mime: string,
): [number, number] {
  if (bytes.length > 4 * 1024 * 1024) throw new Error("图片上限为 4 MB");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let width = 0,
    height = 0;
  if (
    mime === "image/png" &&
    bytes.length >= 24 &&
    [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v) &&
    String.fromCharCode(...bytes.slice(12, 16)) === "IHDR"
  ) {
    width = view.getUint32(16);
    height = view.getUint32(20);
  } else if (mime === "image/jpeg" && bytes[0] === 255 && bytes[1] === 216) {
    let pos = 2;
    while (pos + 4 <= bytes.length) {
      if (bytes[pos++] !== 255) break;
      while (bytes[pos] === 255) pos++;
      const marker = bytes[pos++];
      if (marker === 217 || marker === 218 || pos + 2 > bytes.length) break;
      if (marker === 1 || (marker >= 208 && marker <= 215)) continue;
      const length = view.getUint16(pos);
      if (length < 2 || pos + length > bytes.length) break;
      if ([192, 193, 194].includes(marker) && length >= 8) {
        height = view.getUint16(pos + 3);
        width = view.getUint16(pos + 5);
        break;
      }
      pos += length;
    }
  }
  if (
    width < 1 ||
    height < 1 ||
    width > 4096 ||
    height > 4096 ||
    width * height > 4_000_000
  )
    throw new Error("仅支持有效 PNG / JPEG，最多 400 万像素、单边 4096 像素");
  return [width, height];
}
export function fitRect(
  width: number,
  height: number,
  mode: "contain" | "cover",
): [number, number, number, number] {
  if (
    width <= 0 ||
    height <= 0 ||
    !Number.isFinite(width) ||
    !Number.isFinite(height)
  )
    throw new Error("无效图片尺寸");
  const scale =
    mode === "contain"
      ? Math.min(SCREEN_WIDTH / width, SCREEN_HEIGHT / height)
      : Math.max(SCREEN_WIDTH / width, SCREEN_HEIGHT / height);
  return [
    (SCREEN_WIDTH - width * scale) / 2,
    (SCREEN_HEIGHT - height * scale) / 2,
    width * scale,
    height * scale,
  ];
}
