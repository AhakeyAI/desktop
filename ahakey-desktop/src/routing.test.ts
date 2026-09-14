import { describe, expect, it } from "vitest";
import { linkLabel, sameRouting, validRouting, routingAvailable, effectivePair, pairingLabel, canReset, type DevicePolicy, type RoutingConfig, type PairingDetails } from "./routing";
describe("two lever targets from three links", () => {
  it("preserves arbitrary pairs only in approve mode; host mode fixes upper USB", () => {
    for (const up of [0,1,2]) for (const down of [0,1,2]) if(up !== down) {
      const c={mode:0,up,down} as RoutingConfig;
      expect(effectivePair(c,true)).toEqual([up,down]);
      expect(effectivePair(c,false)).toEqual([up===2?1-down:up,down===2?1-up:down]);
    }
    expect(effectivePair({mode:1,up:2,down:1},false)).toEqual([0,1]);
    expect(effectivePair({mode:1,up:2,down:0},false)).toEqual([1,0]);
  });
  it("never labels unknown pairing information as unpaired", () => {
    expect(pairingLabel(null,0)).toBe("配对详情未知");
    const d={paired:2,connected:6,ready:4} as PairingDetails;
    expect(pairingLabel(d,1)).toBe("已配对 · 已连接 · 未就绪");
    expect(pairingLabel(d,0)).toBe("未绑定配对 · 未连接");
    expect(pairingLabel(d,2)).toBe("USB 可输入");
  });
  it("allows USB configuration with disconnected BLE without automatic fallback", () => {
    expect(routingAvailable("usb", true, false)).toBe(true);
    expect(routingAvailable("ble", true, false)).toBe(false);
    expect(routingAvailable("usb", false, true)).toBe(false);
    expect(routingAvailable("ble", false, true)).toBe(true);
  });
  it("accepts six approve pairs and only two fixed-upper host pairs", () => {
    for (const mode of [0, 1]) for (const up of [0, 1, 2]) for (const down of [0, 1, 2])
      expect(validRouting({ mode, up, down } as RoutingConfig)).toBe(up !== down && (mode===0 || (up===2&&down<2)));
    expect(validRouting({ mode: 1, up: 3, down: 0 } as unknown as RoutingConfig)).toBe(false);
  });
  it("never enables reset on BLE, absent USB, unknown firmware or pending operation", () => {
    const p={fixedUpperUsb:true,state:0,target:null,error:0,request:0,paired:3} as DevicePolicy;
    expect(canReset("usb",p,false,true)).toBe(true);
    expect(canReset("ble",p,false,true)).toBe(false);
    expect(canReset("usb",p,false,false)).toBe(false);
    expect(canReset("usb",null,false,true)).toBe(false);
    expect(canReset("usb",p,true,true)).toBe(false);
    expect(canReset("usb",{...p,state:1},false,true)).toBe(false);
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
