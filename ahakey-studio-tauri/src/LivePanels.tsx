import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Settings, Snapshot } from "./contracts";

type Props = { snapshot: Snapshot | null; draft: Settings; patch: (value: Partial<Settings>) => void; changed: boolean; fail: (message: string) => void };
function useAction(fail: Props["fail"]) {
  const [pending, setPending] = useState("");
  const actionVersion = useRef(0);
  const run = async (command: string, args?: Record<string, unknown>) => {
    const version = ++actionVersion.current;
    setPending(command);
    try { await invoke(command, args); } catch (error) { if (version === actionVersion.current) fail(String(error)); } finally { if (version === actionVersion.current) setPending(""); }
  };
  return { pending, run };
}

export function VoiceControls({ snapshot: s, changed, fail }: Props) {
  const { pending, run } = useAction(fail);
  const external = s?.settings.provider === "wechat" || s?.settings.provider === "windows-native";
  const title = s?.settings.provider === "wechat" ? "微信语音" : "Windows 听写";
  if (external) return <section className="surface external-session">
    <div className="section-heading"><h2>{title}</h2><span>{s?.speech.recording?"语音进行中":s?.nativeKeyTestEnabled?"语音键就绪":"监听未开启"}</span></div>
    <p className="section-description">{changed?"正在应用选择…":s?.nativeKeyTestEnabled?`在目标输入框${s.settings.triggerMode==="hold"?"按住语音键，松开结束":"按一下语音键开始，再按一下结束"}。无需打开本地录音预览。`:"先开启上方语音键监听，再回到输入框使用。"}</p>
    {s?.speech.recording&&<div className="button-row"><button className="secondary" disabled={!!pending} onClick={()=>run("finish_speech")}>结束语音</button></div>}
  </section>;
  const ready = s && (s.settings.provider === "local" ? s.modelInstalled : s.cloudConfigured);
  return <section className="surface">
    <div className="section-heading"><h2>录音与预览</h2><span>{s?.speech.recording?"正在使用麦克风":"按需开始"}</span></div>
    <p role="status" className="section-description">{s?.speech.message??"请打开原生客户端"}</p>
    <div className="button-row">
      <button className="primary" disabled={!ready||!!pending||changed||s?.speech.recording||s?.speech.phase==="transcribing"} onClick={()=>run("start_speech")}>开始录音预览</button>
      <button className="secondary" disabled={!s?.speech.recording||!!pending} onClick={()=>run("finish_speech")}>结束识别</button>
      <button className="text-button" disabled={!s||(s.speech.phase==="idle"&&!s.speech.recording)} onClick={()=>run("cancel_speech")}>取消</button>
      <button className="text-button" disabled={s?.caption.phase!=="final"||!s.caption.text} onClick={()=>navigator.clipboard.writeText(s!.caption.text).catch(e=>fail(String(e)))}>复制文字</button>
    </div>
    {!ready&&<p className="hint">请先在设置中{s?.settings.provider==="doubao"?"配置豆包 API 凭据":"下载或导入模型"}。</p>}
    {s?.settings.provider==="doubao"&&<p className="hint">录音会发送到火山引擎，可能产生账号费用。</p>}
    <details className="compact-details"><summary>输入与隐私说明</summary><p>界面按钮仅预览。自动输入请先聚焦目标输入框，再按设备语音键。仅输入最终文字，焦点变化时保留预览。本地字幕约每 800 ms 重算最近 12 秒，最终结果可能修正；最长录音 120 秒。本地音频不上传，不自动回退云端。</p></details>
  </section>;
}

export function DeviceInformation({ snapshot: s }: { snapshot: Snapshot | null }) {
  const device=s?.device;
  const status=device?.status;
  const source=device?.transport === "usb" ? "USB" : device?.transport === "ble" ? "蓝牙" : null;
  return <section className="surface" aria-labelledby="device-info-title">
    <div className="section-heading"><h2 id="device-info-title">设备信息</h2><span>{source ? `由 ${source} 读取` : "等待设备数据"}</span></div>
    <p className="section-description">USB 数据线即插即读，不需要蓝牙配对。两种连接同时可用时，本页优先显示 USB 读回的信息。</p>
    <div className="connection-summary" aria-label="连接状态">
      <span>{s?.usb?.status ? "USB 已连接 · 自动检测" : s?.usb?.supported ? "USB 未检测到有效设备" : "USB 信息读取暂仅支持 Windows"}</span>
      <span>{s?.bleReady ? "蓝牙已连接" : "蓝牙未连接（不影响 USB）"}</span>
    </div>
    <dl className="about-list">
      <div><dt>设备</dt><dd>{device?.name ?? "未检测到键盘"}</dd></div>
      <div><dt>信息来源</dt><dd>{source ?? "—"}</dd></div>
      <div><dt>电量</dt><dd>{status && status.batteryLevel <= 100 ? `${status.batteryLevel}%` : "未知 · 等待有效数据"}</dd></div>
      <div><dt>固件返回版本</dt><dd>{status ? `${status.firmwareMain}.${status.firmwareSub}（兼容字段）` : "—"}</dd></div>
      <div><dt>设备当前模式</dt><dd>{status ? s?.settings.profiles[status.workMode]?.name ?? `模式 ${status.workMode}` : "—"}</dd></div>
      <div><dt>灯条亮度</dt><dd>{status && status.lightBrightness >= 1 && status.lightBrightness <= 100 ? `${status.lightBrightness}%` : "—"}</dd></div>
    </dl>
    <p className="hint">USB 信息约每 2 秒自动检查；读取失败会清除旧状态。连接可用不等于当前输入目标，拨杆的目标设置见下方。</p>
    {s?.usb?.error && <details className="compact-details"><summary>USB 读取详情</summary><p className="message error">{s.usb.error}</p></details>}
  </section>;
}

export function DevicePanel({ snapshot: s, changed, fail }: Props) {
  const { pending, run } = useAction(fail);
  const phase = s?.ble?.phase;
  return <section className="surface">
    <div className="section-heading"><h2>蓝牙连接</h2><span>{phase === "ready" ? "蓝牙已连接" : phase === "connecting" ? "连接并订阅中…" : "蓝牙未连接"}</span></div>
    <p className="section-description">仅管理蓝牙扫描、配对后的连接与重连。USB 不需要在这里连接；蓝牙未连接不会影响有线输入和上方设备信息。</p>
    <p className="reconnect-status" role="status">{phase === "ready" ? "自动重连已开启 · 设备休眠掉线后会在后台重试" : s?.bleRecovery.connecting ? `正在尝试连接（第 ${s.bleRecovery.attempt} 次）… 可随时停止` : s?.bleRecovery.enabled ? "等待设备恢复 · 唤醒键盘后会自动重连，无需手动点击" : s?.settings.savedDevice ? "已暂停自动重连 · 点击连接上次设备可恢复" : "首次连接设备后，将自动记住并在掉线后重连"}</p>
    {(s?.bleError || s?.ble?.error) && <details className="compact-details"><summary>最近一次连接详情</summary><p className="message error">{s.bleError || s.ble?.error}</p></details>}
    {phase === "ready" && s?.settingsNotice && <p className="hint" role="status">{s.settingsNotice}</p>}
    <p className="hint">蓝牙设备：{s?.ble?.device?.name ?? "尚未选择"}。首次请先在系统蓝牙设置完成键盘配对；Rust 直接连接，不使用 BLE TCP bridge。</p>
    <div className="button-row">
      <button className="primary" disabled={!s || !!pending || s.bleRecovery.connecting} onClick={() => run("scan_devices")}>{pending === "scan_devices" ? "扫描中（4 秒）…" : "扫描设备"}</button>
      <button className="secondary" disabled={!s || !!pending || s.bleRecovery.connecting || !s.settings.savedDevice} onClick={() => run("connect_device", { id: s!.settings.savedDevice })}>连接上次设备</button>
      <button className="secondary" disabled={!s || pending === "disconnect_device" || (!s.bleRecovery.enabled && !s.ble?.device)} onClick={() => run("disconnect_device")}>{phase === "ready" ? "断开" : "停止自动重连"}</button>
    </div>
    <div className="device-results" aria-live="polite">{s?.devices.filter(device => device.isCandidate).map(device => <div className="setting-row" key={device.id}>
      <div><strong>{device.name || "未命名设备"}</strong><p>{device.isCandidate ? "AhaKey 候选设备" : "其他蓝牙设备"} · {device.rssi ?? "—"} dBm</p></div>
      <button className="secondary" disabled={!!pending || s.bleRecovery.connecting || !device.isCandidate} onClick={() => run("connect_device", { id: device.id })}>连接</button>
    </div>)}</div>
    <div className="setting-row"><div><strong>通过蓝牙写入四个模式与灯效</strong><p>此写入入口目前仍使用蓝牙；USB 设备信息与拨杆路由不受影响。</p></div>
      <button className="secondary" disabled={!s?.bleReady || !!pending || changed} onClick={() => run("write_profiles")}>写入设备</button></div>
  </section>;
}

const effects = ["关闭", "单点流动", "彩虹流动", "彩虹波浪", "慢速彩虹", "呼吸灯", "中间常亮", "输入涟漪", "彗星拖尾", "扫描灯条", "中心脉冲", "警示闪烁", "完成扫光", "蓝色思考", "低电提醒", "充电流动", "等待批准"];
const states = ["通知提醒", "等待批准", "工具完成", "工具执行前", "会话开始", "AI 停止", "任务完成", "提交输入", "会话结束"];
export function HookPanel({ snapshot: s, draft, patch, changed, fail }: Props) {
  const { pending, run } = useAction(fail);
  const profile = draft.profiles.find(p => p.id === draft.activeProfile)!;
  const setEffect = (index: number, value: number) => patch({ profiles: draft.profiles.map(p => p.id === profile.id ? { ...p, lightEffects: p.lightEffects.map((v, i) => i === index ? value : v) } : p) });
  return <section className="surface">
    <div className="section-heading"><h2>Hook 与灯效 · {profile.name}</h2><span>{s?.hookPort ? `本机端口 ${s.hookPort}` : "事件接收已关闭"}</span></div>
    <p className="section-description">接收已有 AhaKey Hook 分发脚本的事件。不会自动修改 Codex / Claude 的配置，也不会自动批准命令；桌面应用须自行提供事件来源。</p>
    <div className="button-row"><button className="secondary" disabled={!s || !!pending} onClick={() => run("set_hooks", { enabled: !s?.hookPort })}>{s?.hookPort ? "关闭事件接收" : "启用事件接收"}</button><span role="status">最近事件：{s?.hookLastEvent ?? "尚未收到"}</span></div>
    <div className="light-mappings">{states.map((name, index) => <div className="setting-row" key={name}>
      <label>{name}<select aria-label={`${name}灯效`} value={profile.lightEffects[index]} onChange={e => setEffect(index, Number(e.target.value))}>{effects.map((effect, value) => <option key={effect} value={value}>{effect}</option>)}</select></label>
      <button className="text-button" disabled={!s?.bleReady || !!pending} onClick={() => run("test_light", { effect: profile.lightEffects[index] })}>预览灯效</button>
    </div>)}</div>
    <label className="setting-row">灯条亮度（{draft.lightBrightness}%）<input aria-label="灯条亮度" type="range" min="1" max="100" value={draft.lightBrightness} onChange={e => patch({ lightBrightness: Number(e.target.value) })} /></label>
    <button className="primary" disabled={!s?.bleReady || !!pending || changed} onClick={() => run("write_profiles")}>将已保存配置写入键盘</button>
    <p className="hint">设置自动保存；模式和亮度在连接后立即应用。完整键位 / 灯效映射需点击写入设备。部分灯效取决于固件支持。</p>
  </section>;
}

export function EnginePanel({ snapshot: s, draft, patch, fail }: Props) {
  const { pending, run } = useAction(fail);
  const [microphones, setMicrophones] = useState<string[]>([]);
  const [source, setSource] = useState("");
  const [token, setToken] = useState("");
  useEffect(() => { if (s) invoke<string[]>("microphone_devices").then(setMicrophones).catch(e => fail(String(e))); }, [!!s]);
  return <>
    <section className="surface"><h2>麦克风与本地模型</h2>
      <label>录音设备<select value={draft.microphone ?? ""} onChange={e => patch({ microphone: e.target.value || null })}><option value="">Windows / 系统默认输入设备</option>{microphones.map(name => <option key={name}>{name}</option>)}</select></label>
      <div className="setting-row"><div><strong>SenseVoice Small INT8</strong><p>原生引擎已内置；权重约 230 MB，默认不下载。本地识别不上传音频。</p></div><span>{s?.modelInstalled ? "模型已安装" : "尚未安装权重"}</span></div>
      <p className="file-path hint">{s?.modelDirectory}</p>
      <label>导入已有模型目录（包含 model.int8.onnx 与 tokens.txt）<input value={source} onChange={e => setSource(e.target.value)} placeholder="模型目录的完整路径" /></label>
      <div className="button-row">
        <button className="secondary" disabled={!s || s.download.busy || s.speech.recording || !!pending} onClick={() => run("prepare_model", { source: null })}>下载并校验权重</button>
        <button className="secondary" disabled={!s || !source.trim() || s.download.busy || s.speech.recording || !!pending} onClick={() => run("prepare_model", { source: source.trim() })}>导入并校验</button>
        <button className="text-button" disabled={!s?.download.busy} onClick={() => run("cancel_model")}>取消下载 / 导入</button>
      </div>
      {s?.download.busy && <progress aria-label="模型准备进度" max="1" value={s.download.progress} />}
      <p role="status" className="hint">{s?.download.message}</p>
    </section>
    <section className="surface"><h2>豆包云端识别</h2>
      <p className="section-description">需要火山引擎语音识别服务的独立 API 凭据。保存密钥不会开始上传；选择豆包并主动开始录音才发送音频，可能产生账号费用。</p>
      <div className="two-columns"><label>App ID<input value={draft.cloudAppId} maxLength={128} onChange={e => patch({ cloudAppId: e.target.value })} /></label>
        <label>资源 ID<select value={draft.cloudResourceId} onChange={e => patch({ cloudResourceId: e.target.value })}>{["volc.bigasr.sauc.duration", "volc.bigasr.sauc.concurrent", "volc.seedasr.sauc.duration", "volc.seedasr.sauc.concurrent"].map(id => <option key={id}>{id}</option>)}</select></label></div>
      <label>Access Token（独立保存，不回显）<input type="password" autoComplete="off" value={token} onChange={e => setToken(e.target.value)} /></label>
      <div className="button-row"><button className="secondary" disabled={!s || !token.trim() || !!pending} onClick={async () => { await run("save_cloud_token", { token: token.trim() }); setToken(""); }}>安全保存 Token</button><button className="text-button" disabled={!s?.cloudConfigured || !!pending} onClick={() => run("clear_cloud_token")}>删除 Token</button><span>{s?.cloudConfigured ? "凭据已保存于系统保护存储" : "未配置凭据"}</span></div>
      <p className="hint">App ID 与资源 ID 自动保存；Token 需单独点击安全保存，不写入普通设置文件或诊断信息。</p>
    </section>
    <section className="surface"><h2>窗口与输入</h2>
      <label className="setting-row">最终文字自动输入原目标<input type="checkbox" checked={draft.autoInsert} onChange={e => patch({ autoInsert: e.target.checked })} /></label>
      <p className="hint">{s?.autoInsertSupported ? "当前支持 Windows。不会自动切换到 Codex 或其他应用。" : "此平台暂仅预览与复制；原生自动输入待验证。"}</p>
      <label className="setting-row">关闭窗口时留在托盘<input type="checkbox" checked={draft.minimizeToTray} onChange={e => patch({ minimizeToTray: e.target.checked })} /></label>
      <p className="hint">使用托盘“退出”完全停止语音、蓝牙与 Hook。语音键会记住明确开启的选择；Hook 接收仍需手动开启。</p>
    </section>
  </>;
}
