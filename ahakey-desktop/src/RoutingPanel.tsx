import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { HostTarget, RoutingConfig, RoutingStatus, RoutingTransport, hostNames, linkLabel, sameRouting, validRouting, routingAvailable } from "./routing";

export function RoutingPanel({ ready, usbSupported = false, generation = 0 }: { ready: boolean; usbSupported?: boolean; generation?: number }) {
  const [transport, setTransport] = useState<RoutingTransport>("usb");
  const available = routingAvailable(transport, usbSupported, ready);
  const [status, setStatus] = useState<RoutingStatus | null>(null);
  const [draft, setDraft] = useState<RoutingConfig>({ mode: 1, up: 0, down: 1 });
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const epoch = useRef(0);
  const gate = useRef(false);
  const read = async () => {
    if (!available || gate.current) return;
    const current = epoch.current;
    gate.current = true; setBusy(true); setError(""); setMessage("");
    try {
      const next = await invoke<RoutingStatus>("get_device_routing", { transport });
      if (current === epoch.current) { setStatus(next); setDraft(next.config); setMessage("已读取设备配置"); }
    } catch (e) {
      if (current === epoch.current) { setStatus(null); setError(`未取得设备确认：${String(e)}。请检查${transport === "usb" ? "USB 数据线" : "系统蓝牙配对"}后重新读取。`); }
    } finally { if (current === epoch.current) { gate.current = false; setBusy(false); } }
  };
  useEffect(() => {
    ++epoch.current;gate.current = false;setBusy(false);setStatus(null);setError("");setMessage("");
    void read();
    return () => { ++epoch.current; };
  }, [transport, available, transport === "ble" ? generation : 0]);
  const apply = async () => {
    if (!available || !status || gate.current || !validRouting(draft)) return;
    const current = epoch.current;
    gate.current = true; setBusy(true); setError(""); setMessage("");
    const submitted = { ...draft };
    try {
      const next = await invoke<RoutingStatus>("set_device_routing", { config: submitted, transport });
      if (current === epoch.current) {
        setStatus(next); setDraft(next.config);
        setMessage(next.routingError ? "设备已保存配置，正在等待旧目标释放按键；可刷新确认。" : "设备已确认保存配置");
      }
    } catch (e) {
      if (current === epoch.current) { setError(`未确认保存成功：${String(e)}。请重新读取设备确认，勿重复连续点击。`); setStatus(null); }
    } finally { if (current === epoch.current) { gate.current = false; setBusy(false); } }
  };
  const edit = (patch: Partial<RoutingConfig>) => { setDraft(v => ({ ...v, ...patch })); setMessage(""); };
  return <section className="surface routing-panel" aria-labelledby="routing-title">
    <div className="section-heading"><h2 id="routing-title">拨杆与输入目标</h2><span>{status ? "上次读取的设备状态" : "需要支持三路路由的固件"}</span></div>
    <p className="section-description">USB ＋双蓝牙最多三路在线，键盘只向当前目标输入。拨杆从三路中选两路切换；离线时不自动转发。</p>
    <label className="routing-transport">配置连接<select value={transport} disabled={busy} onChange={e => setTransport(e.target.value as RoutingTransport)}>
      <option value="usb">USB 数据线（不依赖蓝牙）</option><option value="ble">当前蓝牙连接</option>
    </select></label>
    <p className="hint">配置连接不是输入目标。屏幕冒号前的 A / B / U 才是当前输入目标，右侧字母仅表示链路就绪。</p>
    {status && <div className="routing-links">{hostNames.map((name, i) => <div key={name} className={status.selected === i ? "selected" : ""}>
      <strong>{name}</strong><span>{linkLabel(status, i as HostTarget)}</span><small>{status.selected === i ? "当前输入目标" : "未选中"}</small>
    </div>)}</div>}
    <fieldset disabled={!available || !status || busy} className="routing-fields">
      <label>拨杆功能<select value={draft.mode} onChange={e => edit({ mode: Number(e.target.value) as 0 | 1 })}>
        <option value={1}>切换输入设备</option><option value={0}>保留批准拨杆（approve）</option>
      </select></label>
      <div className="two-columns">{(["up", "down"] as const).map((side, i) => <label key={side}>{draft.mode === 1 ? (i ? "拨杆下端" : "拨杆上端") : (i ? "备用输入目标" : "首个输入目标")}
        <select value={draft[side]} onChange={e => edit({ [side]: Number(e.target.value) as HostTarget })}>
          {hostNames.map((name, target) => <option key={name} value={target}>{name}</option>)}
        </select>
      </label>)}</div>
    </fieldset>
    {!validRouting(draft) && <p className="message error" role="alert">请选两个不同的输入目标。</p>}
    <p className="hint">{draft.mode === 1 ? "切设备模式不发出自动批准状态；拨杆中间位置保持原目标。" : "批准模式下，双击独立电源 / 模式键切换这两个输入目标。保留设备的旧批准状态协议，但 Rust 客户端不会代你开启外部工具自动批准。"}</p>
    <p className="hint">蓝牙 A / B 按首次配对分配并记住。USB 输入不需要客户端运行；USB 配置通道暂仅支持 Windows。设置不会随 profile 自动覆盖。</p>
    <div className="button-row">
      <button className="primary" disabled={!available || !status || busy || !validRouting(draft) || sameRouting(draft, status.config)} onClick={() => void apply()}>{busy ? "等待设备…" : "应用到键盘"}</button>
      <button className="secondary" disabled={!available || busy} onClick={() => void read()}>重新读取设备</button>
    </div>
    <p className="hint" role="status">{!available ? transport === "usb" ? "请在 Windows 原生预览客户端中使用 USB 配置，或切换蓝牙配置。" : "请先在系统蓝牙设置中配对，再连接客户端；也可切换 USB 配置。" : busy ? "等待设备回传确认…" : message}</p>
    {error && <p className="message error" role="alert">{error}</p>}
  </section>;
}
