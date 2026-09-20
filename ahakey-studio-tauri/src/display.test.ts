import { describe, expect, it } from "vitest";
import {
  defaultCards,
  encodeRgb565,
  fitRect,
  imageDimensions,
  percentage,
} from "./display";
describe("display assets", () => {
  it("encodes known colors big endian", () => {
    const p = new Uint8ClampedArray(160 * 80 * 4);
    p.set([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]);
    expect([...encodeRgb565(p).slice(0, 6)]).toEqual([248, 0, 7, 224, 0, 31]);
    expect(encodeRgb565(p)).toHaveLength(25600);
  });
  it("rejects malformed frame lengths", () =>
    expect(() => encodeRgb565(new Uint8ClampedArray(4))).toThrow());
  it("fits without stretching", () => {
    expect(fitRect(100, 100, "contain")).toEqual([40, 0, 80, 80]);
    expect(fitRect(100, 100, "cover")).toEqual([0, -40, 160, 160]);
  });
  it("rejects corrupt and oversized headers before decoding", () => {
    expect(() => imageDimensions(new Uint8Array(30), "image/png")).toThrow();
    const b = new Uint8Array(24);
    b.set([137, 80, 78, 71, 13, 10, 26, 10]);
    b.set([73, 72, 68, 82], 12);
    const v = new DataView(b.buffer);
    v.setUint32(16, 100000);
    v.setUint32(20, 80);
    expect(() => imageDimensions(b, "image/png")).toThrow();
    v.setUint32(16, 160);
    expect(imageDimensions(b, "image/png")).toEqual([160, 80]);
  });
});
describe("quota cards", () => {
  it("never renders missing or invalid as zero", () => {
    expect(percentage(null)).toBe("未知");
    expect(percentage(NaN)).toBe("未知");
    expect(percentage(101)).toBe("未知");
    expect(percentage(0)).toBe("0%");
  });
  it("has four independent providers with no automatic account queries", () => {
    const c = defaultCards();
    expect(c.accounts.map((a) => a.provider)).toEqual([
      "minimax",
      "glm",
      "kimi",
      "codex",
    ]);
    expect(c.autoRefresh).toBe(false);
    expect(JSON.stringify(c)).not.toContain("apiKey");
  });
});
