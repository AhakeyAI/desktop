import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { effectiveKeys, KeyBinding, Settings, Snapshot } from "./contracts";

export function FourKeysPanel({snapshot:s,draft,patch,changed,fail}: {
  snapshot:Snapshot|null; draft:Settings; patch:(value:Partial<Settings>)=>void; changed:boolean; fail:(message:string)=>void;
}) {
  const [selected,setSelected]=useState(0);
  const [confirmed,setConfirmed]=useState(false);
  const [busy,setBusy]=useState(false);
  const profile=draft.profiles.find(p=>p.id===draft.activeProfile)!;
  const keys=effectiveKeys(profile);
  const binding=keys[selected];
  const isVoice=binding.action==="voice";
  const voiceCount=keys.filter(k=>k.action==="voice").length;
  useEffect(()=>{setConfirmed(false);setSelected(0);},[profile.id]);
  const update=(value:Partial<KeyBinding>)=>{
    setConfirmed(false);
    patch({profiles:draft.profiles.map(p=>p.id===profile.id?{...p,keys:keys.map((k,i)=>i===selected?{...k,...value}:k)}:p)});
  };
  const run=async(command:string,args:Record<string,unknown>)=>{
    setBusy(true);try{await invoke(command,args);}catch(e){fail(String(e));}finally{setBusy(false);}
  };
  const observation=s?.keyObservation;
  return <section className="surface" aria-labelledby="four-keys-title">
    <div className="section-heading"><h2 id="four-keys-title" tabIndex={-1}>四个实体按键 · {profile.name}</h2><span>点击按键逐一编辑</span></div>
    <div className="four-key-grid" role="group" aria-label="选择实体按键">
      {keys.map((key,index)=><button key={index} aria-pressed={selected===index} className={`physical-key ${selected===index?"chosen":""}`} onClick={()=>setSelected(index)}>
        <span>按键 {index+1}</span><strong>{key.action==="voice"?"语音输入":key.action==="disabled"?"禁用":key.shortcut||"待设置"}</strong><small>{key.label || `Key ${index+1}`}</small>
      </button>)}
    </div>
    <div className="two-columns key-edit-fields">
      <label>按键 {selected+1} 的功能<select value={binding.action} onChange={e=>update({action:e.target.value as KeyBinding["action"],shortcut:e.target.value==="shortcut"?binding.shortcut||"Enter":""})}>
        <option value="voice">语音输入（跟随语音页渠道）</option><option value="shortcut">快捷键 / 组合键</option><option value="disabled">禁用此键</option>
      </select></label>
      <label>按键 {selected+1} 的显示名称<input maxLength={20} value={binding.label} onChange={e=>update({label:e.target.value})}/></label>
    </div>
    {binding.action==="shortcut" && <label className="key-shortcut-label">按键 {selected+1} 的快捷键<input aria-label={`按键 ${selected+1} 的快捷键`} aria-describedby="shortcut-help" value={binding.shortcut} maxLength={80} placeholder="例如 Ctrl+Enter、Ctrl+Shift+V、Backspace" aria-invalid={!binding.shortcut.trim()} onChange={e=>update({shortcut:e.target.value})}/><span className="hint" id="shortcut-help">支持字母、数字、F1–F12、Enter、Escape、Backspace、方向键及 Ctrl / Shift / Alt / Win 组合。F17/F18 专用于语音。</span></label>}
    {isVoice && <p className="hint">使用语音页选择的渠道（当前 {draft.provider}）与触发方式（{draft.triggerMode==="hold"?"按住说话":"按一下开始 / 停止"}）。固件发出 F17/F18，Rust 再启动识别。</p>}
    {voiceCount>1 && <p className="message error" role="alert">每个模式只能指定一个语音键，请把多余的语音键改为快捷键或禁用。</p>}
    <p className="hint">编辑会自动保存到本机，但不会自动覆盖键盘。快捷键由键盘直接发往当前输入框，不经过语音识别。名称在固件上仅支持英文字符。</p>
    <div className="key-write-area">
      <label><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/> 我确认覆盖 {profile.name} 模式的四键，不修改其他模式或灯效</label>
      <div className="button-row"><button className="primary" disabled={!s?.bleReady || changed || busy || !confirmed || voiceCount>1} onClick={()=>run("write_current_keys",{confirmed:true})}>{busy?"正在处理…":"写入当前模式四键"}</button></div>
      <p role="status" className="hint">{s?.keyWriteNotice ?? "请先连接键盘"}</p>
    </div>
    <div className="setting-row"><div><strong>语音键监听：{s?.nativeKeyTestEnabled?"已开启":"已关闭"}</strong><p>明确开启后会记住选择，下次启动自动恢复；不会自动开始录音。</p></div>
      <button className="secondary" disabled={!s || busy} aria-pressed={s?.nativeKeyTestEnabled??false} onClick={()=>run("set_key_test",{enabled:!s?.nativeKeyTestEnabled})}>{s?.nativeKeyTestEnabled?"停用设备语音键":"启用设备语音键"}</button>
    </div>
    <p className="hint" role="status">{observation?.events?`最近收到 ${observation.key} ${observation.pressed?"按下":"松开"}，本次共 ${observation.events} 个事件。`:"尚未收到 F17/F18。写入四键并启用监听后，在目标输入框按实物语音键检查此状态。"}</p>
    <p className="hint">如果非语音键也没反应，请先确认当前模式四键已写入、Windows 已连接键盘，并把光标放进一个可输入的文本框。</p>
  </section>;
}
