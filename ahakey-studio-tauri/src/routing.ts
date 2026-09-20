export type HostTarget = 0 | 1 | 2;
export type RoutingTransport = "usb" | "ble";
export interface HostInfo { name: string | null; system: string | null }
export interface DevicePolicy {fixedUpperUsb:boolean;state:number;target:number|null;error:number;request:number;paired:number}
export function canReset(transport:RoutingTransport,policy:DevicePolicy|null,busy:boolean,usbPresent?:boolean|null):boolean{
  return transport==="usb"&&usbPresent!==false&&!!policy&&policy.state!==1&&!busy;
}
export function reportedHostLabel(info: HostInfo | undefined): string {
  if (!info) return "设备名称未读取";
  if (!info.name && !info.system) return "名称未上报";
  return [info.name || "主机名未知", info.system].filter(Boolean).join(" · ");
}
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
export interface PairingDetails {
  paired: number; connected: number; ready: number; effectiveUp: HostTarget; effectiveDown: HostTarget;
  wired: boolean; radioState: number; pairingSlot: 0 | 1 | null; remainingSeconds: number;
  bondCount: number; lastReason: number; lastHci: number; pending: boolean; selected: HostTarget; rawLinks: number;
}
export function effectivePair(config: RoutingConfig, wired: boolean): [HostTarget, HostTarget] {
  if(config.mode===1)return [wired?2:(1-config.down) as HostTarget,config.down];
  const replace = (target: HostTarget, other: HostTarget): HostTarget => !wired && target === 2 ? (1 - other) as HostTarget : target;
  return [replace(config.up, config.down), replace(config.down, config.up)];
}
export function pairingLabel(details: PairingDetails | null, target: HostTarget): string {
  if (!details) return "配对详情未知";
  if (target === 2) return details.ready & 4 ? "USB 可输入" : details.connected & 4 ? "USB 已连接 · 未就绪" : "USB 未连接";
  const paired = details.paired & (1 << target);
  return `${paired ? "已配对" : "未绑定配对"} · ${details.ready & (1 << target) ? "已连接 · 可输入" : details.connected & (1 << target) ? "已连接 · 未就绪" : "未连接"}`;
}
export function pairingReason(code: number): string {
  return ({ 0: "无", 4: "配对元数据异常", 5: "身份不可用", 6: "槽位未能分配", 7: "槽位身份冲突", 8: "存储失败", 9: "配对失败", 10: "安全请求失败", 11: "握手超时", 12: "连接断开", 13: "配对已禁用", 14: "密钥长度异常", 15: "等待 SDK 完成绑定" } as Record<number, string>)[code] ?? `错误 ${code}`;
}
export const hostNames = ["蓝牙 A", "蓝牙 B", "USB 有线"] as const;
export function validRouting(config: RoutingConfig): boolean {
  return [0, 1].includes(config.mode) && [0, 1, 2].includes(config.up)
    && [0, 1, 2].includes(config.down) && config.up !== config.down
    && (config.mode===0 || (config.up===2 && config.down<2));
}
export function sameRouting(a: RoutingConfig, b: RoutingConfig): boolean {
  return a.mode === b.mode && a.up === b.up && a.down === b.down;
}
export function linkLabel(status: RoutingStatus, target: HostTarget): string {
  return status.ready & (1 << target) ? "可输入"
    : status.connected & (1 << target) ? "已连接 · 未就绪" : "离线";
}
