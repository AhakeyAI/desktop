export type HostTarget = 0 | 1 | 2;
export type RoutingTransport = "usb" | "ble";
export function routingAvailable(transport: RoutingTransport, usbSupported: boolean, bleReady: boolean): boolean {
  return transport === "usb" ? usbSupported : bleReady;
}
export interface RoutingConfig { mode: 0 | 1; up: HostTarget; down: HostTarget }
export interface RoutingStatus {
  config: RoutingConfig;
  selected: HostTarget;
  connected: number;
  ready: number;
  lever: number;
  routingError: number;
}
export const hostNames = ["蓝牙 A", "蓝牙 B", "USB 有线"] as const;
export function validRouting(config: RoutingConfig): boolean {
  return [0, 1].includes(config.mode) && [0, 1, 2].includes(config.up)
    && [0, 1, 2].includes(config.down) && config.up !== config.down;
}
export function sameRouting(a: RoutingConfig, b: RoutingConfig): boolean {
  return a.mode === b.mode && a.up === b.up && a.down === b.down;
}
export function linkLabel(status: RoutingStatus, target: HostTarget): string {
  return status.ready & (1 << target) ? "可输入"
    : status.connected & (1 << target) ? "已连接 · 未就绪" : "离线";
}
