import { describe, expect, it } from "vitest";
import { linkLabel, sameRouting, validRouting, routingAvailable, type RoutingConfig } from "./routing";
describe("two lever targets from three links", () => {
  it("allows USB configuration with disconnected BLE without automatic fallback", () => {
    expect(routingAvailable("usb", true, false)).toBe(true);
    expect(routingAvailable("ble", true, false)).toBe(false);
    expect(routingAvailable("usb", false, true)).toBe(false);
    expect(routingAvailable("ble", false, true)).toBe(true);
  });
  it("accepts exactly six ordered pairs in either mode", () => {
    for (const mode of [0, 1]) for (const up of [0, 1, 2]) for (const down of [0, 1, 2])
      expect(validRouting({ mode, up, down } as RoutingConfig)).toBe(up !== down);
    expect(validRouting({ mode: 1, up: 3, down: 0 } as unknown as RoutingConfig)).toBe(false);
  });
  it("distinguishes connectivity from readiness and configuration equality", () => {
    const config: RoutingConfig = { mode: 1, up: 2, down: 0 };
    const s = { config, selected: 2 as const, connected: 5, ready: 1, lever: 0, routingError: 0 };
    expect(linkLabel(s, 0)).toBe("可输入");
    expect(linkLabel(s, 1)).toBe("离线");
    expect(linkLabel(s, 2)).toBe("已连接 · 未就绪");
    expect(sameRouting(config, { ...config })).toBe(true);
    expect(sameRouting(config, { ...config, up: 0, down: 2 })).toBe(false);
  });
});
