import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { HostInfo, reportedHostLabel, DevicePolicy, canReset } from "./routing";
import { HostTarget, RoutingConfig, RoutingStatus, RoutingTransport, PairingDetails, hostNames, linkLabel, sameRouting, validRouting, effectivePair, pairingLabel, pairingReason } from "./routing";

export function RoutingPanel({ ready, usbSupported = false, usbPresent, generation = 0 }: { ready: boolean; usbSupported?: boolean; usbPresent?:boolean|null; generation?: number }) {
  const [transport, setTransport] = useState<RoutingTransport>("usb");
  const available = usbSupported || ready;
  const [policy,setPolicy]=useState<DevicePolicy|null>(null);
  const [policyError,setPolicyError]=useState("");
  const [resetTarget,setResetTarget]=useState<0|1|2|null>(null);
  const [status, setStatus] = useState<RoutingStatus | null>(null);
  const [draft, setDraft] = useState<RoutingConfig>({ mode: 1, up: 2, down: 1 });
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [pairing, setPairing] = useState<PairingDetails | null>(null);
  const [pairingError, setPairingError] = useState("");
  const [confirmSwap, setConfirmSwap] = useState(false);
  const [hosts, setHosts] = useState<HostInfo[] | null>(null);
  const [hostError, setHostError] = useState("");
  const [aliases, setAliases] = useState<[string,string]>(["",""]);
  const [savedAliases, setSavedAliases] = useState<[string,string] | null>(null);
  const [aliasBusy, setAliasBusy] = useState(false);
  const [aliasMessage, setAliasMessage] = useState("");
  useEffect(() => {
    let active=true;
    invoke<[string,string]>("get_host_aliases").then(v => {
      if(active){setAliases(v);setSavedAliases(v);}
    }).catch(e => {if(active)setAliasMessage(`备注读取失败：${String(e)}`);});
    return () => {active=false;};
  }, []);
  const saveAliases = async () => {
    if(!savedAliases || aliasBusy) return;
    setAliasBusy(true);setAliasMessage("");
    try {
      const next=await invoke<[string,string]>("set_host_aliases",{aliases});
      setAliases(next);setSavedAliases(next);setAliasMessage("槽位备注已保存在本机，未修改键盘配对。");
    } catch(e){setAliasMessage(`备注未保存：${String(e)}`);}
    finally{setAliasBusy(false);}
  };
  const epoch = useRef(0);
  const gate = useRef(false);
  const loadState = async (current: number, chosen:RoutingTransport=transport) => {
    if(current===epoch.current){setHosts(null);setHostError("");setPolicy(null);}
    const next = await invoke<RoutingStatus>("get_device_routing", { transport:chosen });
    if (current !== epoch.current) return;
    setStatus(next); setDraft(next.config); setPairing(null); setPairingError("");
    try {
      const details = await invoke<PairingDetails>("get_device_pairing", { transport:chosen });
      if (current === epoch.current) setPairing(details);
    } catch (e) { if (current === epoch.current) setPairingError(`配对详情不可用：${String(e)}`); }
    try {
      const nextHosts=await invoke<HostInfo[]>("get_device_hosts",{transport:chosen});
      if(current===epoch.current)setHosts(nextHosts);
    } catch(e){if(current===epoch.current)setHostError(`名称读取不可用：${String(e)}`);}
    try{
      const nextPolicy=await invoke<DevicePolicy>("get_device_policy",{transport:chosen});
      if(current===epoch.current){setPolicy(nextPolicy);setPolicyError("");}
    }catch(e){if(current===epoch.current){setPolicy(null);setPolicyError(String(e));}}
  };
  const read = async () => {
    if (!available || gate.current) return;
    const current = epoch.current;
    gate.current = true; setBusy(true); setError(""); setMessage("");
    try {
      const chosen=await invoke<RoutingTransport>("select_configuration_transport");
      if(current!==epoch.current)return;
      setTransport(chosen);
      await loadState(current,chosen);
      if (current === epoch.current) setMessage("已读取设备配置");
    } catch (e) {
      if (current === epoch.current) { setStatus(null); setError(`未取得设备确认：${String(e)}。请检查${transport === "usb" ? "USB 数据线" : "系统蓝牙配对"}后重新读取。`); }
    } finally { if (current === epoch.current) { gate.current = false; setBusy(false); } }
  };
  useEffect(() => {
    ++epoch.current;gate.current = false;setBusy(false);setStatus(null);setPolicy(null);setResetTarget(null);setPairing(null);setHosts(null);setHostError("");setPairingError("");setConfirmSwap(false);setError("");setMessage("");
    void read();
    return () => { ++epoch.current; };
  }, [available, usbPresent, generation, ready]);
  const apply = async () => {
    if (!available || !status || gate.current || !validRouting(draft)) return;
    const current = epoch.current;
    gate.current = true; setBusy(true); setError(""); setMessage("");
    const submitted = { ...draft };
    try {
      const next = await invoke<RoutingStatus>("set_device_routing", { config: submitted, transport });
      if (current === epoch.current) {
        setStatus(next); setDraft(next.config);
        setPairing(null);
        await loadState(current);
        if (current !== epoch.current) return;
        setMessage(next.routingError ? "设备已保存配置，正在等待旧目标释放按键；可刷新确认。" : "设备已确认保存配置");
      }
    } catch (e) {
      if (current === epoch.current) { setError(`未确认保存成功：${String(e)}。请重新读取设备确认，勿重复连续点击。`); setStatus(null); }
    } finally { if (current === epoch.current) { gate.current = false; setBusy(false); } }
  };
  const edit = (patch: Partial<RoutingConfig>) => { setDraft(v => ({ ...v, ...patch })); setMessage(""); };
  const manage = async (action: "swapSlots" | "retry") => {
    if (!available || !pairing || gate.current || (action === "swapSlots" && !confirmSwap)) return;
    const current = epoch.current; let acknowledged = false; gate.current = true; setBusy(true); setError(""); setMessage("");
    try {
      await invoke("manage_device_pairing", { action, transport });
      acknowledged = true;
      await loadState(current);
      if (current === epoch.current) { setConfirmSwap(false); setMessage(action === "swapSlots" ? "设备已确认互换 A/B，原配对保留。" : "设备已确认重新尝试连接，输入目标未改变。"); }
    } catch (e) { if (current === epoch.current) { setError(`${acknowledged ? "操作已确认，但刷新失败" : "操作未确认"}：${String(e)}。请重新读取，勿重复提交。`); setPairing(null); setConfirmSwap(false); } }
    finally { if (current === epoch.current) { gate.current = false; setBusy(false); } }
  };
  const wiredPair = effectivePair(draft, true), wirelessPair = effectivePair(draft, false);
  const resetAllowed=canReset(transport,policy,busy,usbPresent);
  const reset = async () => {
    if(!resetAllowed || resetTarget===null || gate.current)return;
    const target=resetTarget,current=epoch.current;
    gate.current=true;setBusy(true);setError("");setMessage("");
    try{
      await invoke<DevicePolicy>("reset_device_pairing",{target});
      if(current!==epoch.current)return;
      setResetTarget(null);await loadState(current);
      if(current===epoch.current)setMessage(`已确认重置${target===2?"全部蓝牙绑定":hostNames[target]}。请在目标电脑的系统蓝牙中删除旧 AhaKey 配对后重新配对。`);
    }catch(e){if(current===epoch.current){setError(`重置未确认完成：${String(e)}。请重新读取，勿重复提交。`);setResetTarget(null);}}
    finally{if(current===epoch.current){gate.current=false;setBusy(false);}}
  };
  const reportHost = async () => {
    if(!ready || gate.current)return;
    const current=epoch.current;gate.current=true;setBusy(true);setHostError("");
    try {
      await invoke("report_this_host");
      if(current!==epoch.current)return;
      await loadState(current);
      if(current===epoch.current)setMessage("本机名称已通过本机蓝牙连接上报。");
    }catch(e){if(current===epoch.current)setHostError(String(e));}
    finally{if(current===epoch.current){gate.current=false;setBusy(false);}}
  };
  const dirty = !!status && !sameRouting(draft, status.config);
  return <section className="surface routing-panel" aria-labelledby="routing-title">
    <div className="section-heading"><h2 id="routing-title">拨杆与输入目标</h2><span>{status ? "上次读取的设备状态" : "需要支持三路路由的固件"}</span></div>
    <p className="section-description">切设备模式：插线时上端固定 USB，拔线后恢复上端蓝牙，下端蓝牙不变。需要固件 0.1.9+。</p>
    <p className="hint" role="status">配置通道：{status ? transport==="usb" ? "USB（自动优先）" : "蓝牙（自动选择）" : "尚未确认"}。重置只通过 USB，失败不会切换通道重发。</p>
    <p className="hint">配置连接不是输入目标。屏幕冒号前的 A / B / U 才是当前输入目标，右侧字母仅表示链路就绪。</p>
    <div className="routing-links">{hostNames.map((name, i) => <div key={name} className={(pairing?.selected ?? status?.selected) === i ? "selected" : ""}>
      <strong>{name}</strong>
      {i<2 && <><span className="host-reported">{reportedHostLabel(hosts?.[i])}</span><small>{hosts?.[i]?.system ? "来源：对端客户端上报 · 上次读取" : "由对端新版客户端提供"}</small></>}
      <span>{pairing ? pairingLabel(pairing, i as HostTarget) : status ? linkLabel(status, i as HostTarget) : "连接状态未读取"}</span>
      <small>{(pairing?.selected ?? status?.selected) === i ? "当前输入目标" : "未选中"}{!pairing && i < 2 ? " · 配对详情未知" : ""}</small>
      {i<2 && <label className="host-alias">槽位备注（仅本机）<input aria-label={`${name}槽位备注`} maxLength={32} disabled={!savedAliases || aliasBusy} placeholder="例如：工作电脑" value={aliases[i]} onChange={e=>{const value=e.target.value;setAliases(v=>i===0?[value,v[1]]:[v[0],value]);setAliasMessage("");}} /></label>}
    </div>)}</div>
    <div className="button-row">
      <button className="secondary" disabled={!savedAliases || aliasBusy || aliases.every((v,i)=>v===savedAliases[i])} onClick={()=>void saveAliases()}>保存槽位备注</button>
      <button className="secondary" disabled={!ready || busy} onClick={()=>void reportHost()}>重新上报本机名称</button>
    </div>
    {aliasMessage && <p className="hint" role="status">{aliasMessage}</p>}
    <p className="hint">自动名称需要固件 0.1.8+，以及对端运行新版客户端并连接蓝牙；仅在系统中配对不会上报名称。名称按 UTF-8 最多 24 字节，断开后清除。备注属于本机槽位，不代表自动识别；互换 A/B 或重新配对后请核对备注。</p>
    {hostError && <p className="hint" role="status">{hostError}；不会影响按键或配对。</p>}
    {pairing && <p className="hint" role="status">USB {pairing.wired ? "已接入" : "未接入"}：当前上 {hostNames[pairing.effectiveUp]}，下 {hostNames[pairing.effectiveDown]}。{pairing.radioState === 3 ? "HOLD：自动重连已暂停，可手动重试。" : pairing.radioState === 2 ? `配对窗口：${pairing.remainingSeconds} 秒（上次读取）。` : "陌生设备配对未开放。"} 最近记录：{pairingReason(pairing.lastReason)}，HCI {pairing.lastHci === 255 ? "未知" : `0x${pairing.lastHci.toString(16).padStart(2, "0")}`}。</p>}
    {pairingError && <p className="hint">{pairingError}；不会将未知状态当成未配对。</p>}
    {pairing && <p className="hint">键盘保存 {pairing.bondCount} 条配对，当前 {pairing.rawLinks} 条蓝牙物理连接。{pairing.pending ? "部分链路正在完成配对或槽位绑定，请稍后重新读取。" : ""}</p>}
    <fieldset disabled={!available || !status || !pairing || !policy || busy} className="routing-fields">
      <label>拨杆功能<select value={draft.mode} onChange={e => {const mode=Number(e.target.value) as 0|1;edit(mode===1?{mode,up:2,down:draft.down<2?draft.down:0}:{mode});}}>
        <option value={1}>切换输入设备</option><option value={0}>保留批准拨杆（approve）</option>
      </select></label>
      {draft.mode===1 ? <label>下端固定蓝牙<select value={draft.down} onChange={e=>edit({up:2,down:Number(e.target.value) as 0|1})}><option value={0}>蓝牙 A</option><option value={1}>蓝牙 B</option></select></label> :
      <div className="two-columns">{(["up", "down"] as const).map((side, i) => <label key={side}>{i ? "备用输入目标" : "首个输入目标"}
        <select value={draft[side]} onChange={e => edit({ [side]: Number(e.target.value) as HostTarget })}>
          {hostNames.map((name, target) => <option key={name} value={target}>{name}</option>)}
        </select>
      </label>)}</div>}
    </fieldset>
    {policy && !validRouting(draft) && <p className="message error" role="alert">请选择有效目标；切设备模式上端固定为 USB / 蓝牙。</p>}
    {policy && pairing && validRouting(draft) && <p className="hint">配置预览：插线为上 {hostNames[wiredPair[0]]} / 下 {hostNames[wiredPair[1]]}；拔线为上 {hostNames[wirelessPair[0]]} / 下 {hostNames[wirelessPair[1]]}。</p>}
    {!policy && status && <p className="hint">新规则及重置暂不可用：{policyError || "等待固件能力确认"}。旧固件的状态仍可读取。</p>}
    <p className="hint">{draft.mode === 1 ? "切设备模式不发出自动批准状态；拨杆中间位置保持原目标。" : "批准模式下，双击独立电源 / 模式键切换这两个输入目标。保留设备的旧批准状态协议，但 Rust 客户端不会代你开启外部工具自动批准。"}</p>
    <p className="hint">蓝牙 A / B 是设备保存的槽位，不是连接先后顺序。USB 配置暂仅支持 Windows。设置不会随 profile 自动覆盖。</p>
    <div className="button-row">
      <button className="secondary" disabled={!available || !pairing || busy || pairing.pending || dirty} onClick={() => void manage("retry")}>重试蓝牙连接</button>
      <button className="secondary" disabled={!available || !pairing || !pairing.paired || busy || pairing.pending || dirty} onClick={() => setConfirmSwap(true)}>互换蓝牙 A/B…</button>
    </div>
    {confirmSwap && <div className="message" role="alert"><p>互换 A/B 标签与槽位关联，保留原配对和实际输入位置。请先松开实体按键。</p><div className="button-row"><button disabled={busy || !pairing} onClick={() => void manage("swapSlots")}>确认互换 A/B</button><button disabled={busy} onClick={() => setConfirmSwap(false)}>取消</button></div></div>}
    <details className="compact-details"><summary>蓝牙重置（仅 USB）</summary>
      <p className="hint">单槽重置保留另一槽、键盘地址及按键设置。全部重置清除 A/B 和旧绑定。请先松开按键。</p>
      <div className="button-row">{([0,1,2] as const).map(target=><button className="secondary" key={target} disabled={!resetAllowed} onClick={()=>setResetTarget(target)}>{target===2?"重置全部蓝牙…":`重置${hostNames[target]}…`}</button>)}</div>
      {!resetAllowed && policy?.state!==1 && <p className="hint">请接入 USB 并读取支持的新固件；蓝牙连接不能执行客户端重置。</p>}
      {policy?.state===1 && <p role="status">设备正在重置{policy.target===2?"全部蓝牙":hostNames[policy.target ?? 0]}，请等待后重新读取。</p>}
      {policy?.state===2 && <p className="hint" role="status">设备确认上次重置已完成：{policy.target===2?"全部蓝牙":hostNames[policy.target ?? 0]}。</p>}
      {policy?.state===3 && <p className="message error" role="alert">上次重置未确认完成（错误 {policy.error}），可能已断开目标或部分清除。请先核对配对状态，不要连续重复提交。</p>}
      {resetTarget!==null && <div className="message error" role="alert"><p>确认清除{resetTarget===2?"全部蓝牙绑定":hostNames[resetTarget]+"绑定"}？目标电脑随后需要删除系统中的旧 AhaKey 配对并重新配对。不会改变键盘蓝牙地址。</p><div className="button-row"><button disabled={!resetAllowed} onClick={()=>void reset()}>确认通过 USB 重置</button><button disabled={busy} onClick={()=>setResetTarget(null)}>取消</button></div></div>}
    </details>
    <p className="hint">硬件长按：选中 A/B 仅重置该槽；USB 位置只提示先选择蓝牙。按住期间移动拨杆会取消本次重置。</p>
    <div className="button-row">
      <button className="primary" disabled={!available || !status || !pairing || !policy || busy || !validRouting(draft) || sameRouting(draft, status.config)} onClick={() => void apply()}>{busy ? "等待设备…" : "应用到键盘"}</button>
      <button className="secondary" disabled={!available || busy} onClick={() => void read()}>重新读取设备</button>
    </div>
    <p className="hint" role="status">{!available ? "请接入 USB，或先在系统配对并连接客户端蓝牙。" : busy ? "等待设备回传确认…" : message}</p>
    {error && <p className="message error" role="alert">{error}</p>}
  </section>;
}
