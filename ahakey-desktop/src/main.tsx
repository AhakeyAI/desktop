import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  AudioLines,
  Bluetooth,
  Check,
  ChevronRight,
  Cloud,
  Command,
  Cpu,
  Keyboard,
  Layers,
  Mic,
  Monitor,
  Radio,
  Settings2,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Subtitles,
  X,
} from "lucide-react";
import {
  acceptCaption,
  Caption,
  phaseLabel,
  previewSettings,
  Profile,
  sameSettings,
  mergeSavedDraft,
  mergeIncomingDraft,
  Settings,
  Snapshot,
  deviceConnectionLabel,
} from "./contracts";
import "./styles.css";
import { DevicePanel, DeviceInformation, EnginePanel, HookPanel, VoiceControls } from "./LivePanels";
import { FourKeysPanel } from "./FourKeysPanel";
import { ProviderPicker } from "./ProviderPicker";
import { DisplayPanel } from "./DisplayPanel";
import { RoutingPanel } from "./RoutingPanel";

type Page = "voice" | "device" | "hooks" | "display" | "settings";
const native = isTauri();
const pages = [
  {
    id: "voice" as const,
    label: "语音",
    icon: Mic,
    description: "让想法，自然成为文字。",
  },
  {
    id: "device" as const,
    label: "设备",
    icon: Keyboard,
    description: "连接键盘，让操作近在手边。",
  },
  {
    id: "hooks" as const,
    label: "按键与灯效",
    icon: Sparkles,
    description: "给每个应用，恰到好处的反馈。",
  },
  {
    id: "display" as const,
    label: "屏幕与卡片",
    icon: Monitor,
    description: "管理图片素材和服务额度。",
  },
  {
    id: "settings" as const,
    label: "设置",
    icon: Settings2,
    description: "按你的习惯，调整每一个细节。",
  },
];

function useNative() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [error, setError] = useState("");
  const refreshRef = useRef<() => Promise<void>>(async () => {});
  const [caption, setCaption] = useState<Caption>({
    phase: "idle",
    text: "",
    sequence: 0,
  });
  useEffect(() => {
    if (!native) return;
    let disposed = false;
    const cleanup: (() => void)[] = [];
    (async () => {
      const off = await listen<Caption>("caption-update", ({ payload }) => {
        if (!disposed) setCaption((current) => acceptCaption(current, payload));
      });
      if (disposed) {
        off();
        return;
      }
      cleanup.push(off);
      const offError = await listen<string>("native-error", ({ payload }) => {
        if (!disposed) setError(payload);
      });
      if (disposed) {
        offError();
        return;
      }
      cleanup.push(offError);
      let refreshing: Promise<void> | null = null;
      let dirty = false;
      const refresh = (): Promise<void> => {
        dirty = true;
        if (refreshing) return refreshing;
        refreshing = Promise.resolve().then(async () => {
          do {
            dirty = false;
            const next = await invoke<Snapshot>("get_snapshot");
            if (!disposed) { setSnapshot(next); setCaption(current => acceptCaption(current, next.caption)); if(next.settingsError) setError(next.settingsError); }
          } while (dirty && !disposed);
        }).catch(e => {if(!disposed) setError(String(e)); throw e;}).finally(() => {refreshing = null;});
        return refreshing;
      };
      refreshRef.current = refresh;
      const offRuntime = await listen("runtime-update", () => {void refresh().catch(() => {});});
      if (disposed) { offRuntime(); return; }
      cleanup.push(offRuntime);
      await refresh();
    })().catch((e) => {
      if (!disposed) setError(String(e));
    });
    return () => {
      disposed = true;
      cleanup.forEach((stop) => stop());
    };
  }, []);
  return { snapshot, setSnapshot, caption, error, setError, refresh: () => refreshRef.current() };
}

function CaptionWindow() {
  const { caption } = useNative();
  return (
    <div className="caption-root">
      <div className="caption-label">
        <AudioLines size={16} aria-hidden="true" /> AhaKey{" "}
        <span>实时预览</span>
        <span className="caption-phase">{phaseLabel(caption.phase)}</span>
      </div>
      <p role="status" aria-live="polite">
        {caption.text || "等待按键 · 此窗口不会获取输入焦点"}
      </p>
    </div>
  );
}

function Badge({
  children,
  good = false,
}: {
  children: React.ReactNode;
  good?: boolean;
}) {
  return (
    <span className={`badge ${good ? "good" : ""}`}>
      <span className="status-dot" />
      {children}
    </span>
  );
}

function App() {
  const { snapshot, caption, error, setError, refresh } = useNative();
  const [page, setPage] = useState<Page>("voice");
  const [draft, setDraft] = useState<Settings>(
    structuredClone(previewSettings),
  );
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [saveFailed, setSaveFailed] = useState(false);
  const saving = useRef(false);
  const latestDraft = useRef(draft);
  latestDraft.current = draft;
  const heading = useRef<HTMLHeadingElement>(null);
  const activePage = pages.find((item) => item.id === page)!;
  const savedSignature = useRef("");
  const nativeBase = useRef<Settings | null>(null);
  const ownChangeId = useRef<string | null>(null);
  const saveSequence = useRef(0);
  useEffect(() => {
    if (snapshot) {
      const signature = JSON.stringify(snapshot.settings);
      if (signature !== savedSignature.current) {
        const base = nativeBase.current;
        const own = snapshot.settingsChangeId !== null && snapshot.settingsChangeId === ownChangeId.current;
        setDraft(current => !base ? structuredClone(snapshot.settings) : own ? { ...current, savedDevice:snapshot.settings.savedDevice, voiceKeysEnabled:snapshot.settings.voiceKeysEnabled } : mergeIncomingDraft(current,base,snapshot.settings));
        nativeBase.current = structuredClone(snapshot.settings);
        savedSignature.current = signature;
      }
    }
  }, [snapshot?.settings, snapshot?.settingsChangeId]);
  const changed = snapshot ? !sameSettings(draft, snapshot.settings) : false;
  const activeProfile = draft.profiles.find(
    (item) => item.id === draft.activeProfile,
  )!;
  const patch = (value: Partial<Settings>) => {
    setDraft((current) => ({ ...current, ...value }));
    setNotice("");
    setSaveFailed(false);
  };

  useEffect(() => {
    if (!snapshot || !changed || busy || saveFailed || snapshot.settingsError) return;
    const timer = setTimeout(() => { void save(); }, 350);
    return () => clearTimeout(timer);
  }, [draft, snapshot?.settings, changed, busy, saveFailed]);

  async function save() {
    if (saving.current) return;
    saving.current = true;
    const submitted = structuredClone(latestDraft.current);
    const base = structuredClone(nativeBase.current ?? submitted);
    const changeId = `ui-${Date.now()}-${++saveSequence.current}`;
    ownChangeId.current = changeId;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const settings = await invoke<Settings>("save_settings", {
        settings: submitted,
        base, changeId,
      });
      setDraft(current => mergeSavedDraft(current, submitted, settings));
      await refresh();
      setSaveFailed(false);
      setNotice("已自动保存并应用到本机。");
    } catch (e) {
      setSaveFailed(true);
      setError(String(e));
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }
  async function test(pressed: boolean) {
    try {
      await invoke("test_caption", { pressed });
    } catch (e) {
      setError(String(e));
    }
  }
  async function keyTest() {
    if (!snapshot) return;
    setBusy(true);
    try {
      const enabled = !snapshot.nativeKeyTestEnabled;
      await invoke("set_key_test", { enabled });
      await refresh();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }
  function updateProfile(profile: Profile) {
    patch({
      profiles: draft.profiles.map((item) =>
        item.id === profile.id ? profile : item,
      ),
    });
  }

  return (
    <div className="app-shell">
      <a className="skip-link" href="#content">
        跳到主要内容
      </a>
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">
            <AudioLines size={26} aria-hidden="true" />
          </div>
          <div>
            AhaKey<span>STUDIO</span>
          </div>
        </div>
        <span className="section-eyebrow">你的输入工作台</span>
        <nav aria-label="主要导航">
          {pages.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              className={page === id ? "nav-item selected" : "nav-item"}
              aria-current={page === id ? "page" : undefined}
              onClick={() => {
                setPage(id);
                requestAnimationFrame(() => heading.current?.focus());
              }}
            >
              <Icon size={20} aria-hidden="true" />
              {label}
              {page === id && <span className="nav-indicator" />}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="build-label">
            <Layers size={16} aria-hidden="true" />
            <span>Rust 原生客户端</span>
          </div>
          <p>
            JavaFX 日常版可继续使用。
            <br />
            此版本独立保存设置。
          </p>
          <div className="version">
            v{snapshot?.version ?? "0.2.0"}{" "}
            <span>
              {snapshot?.platform ?? (native ? "正在连接…" : "浏览器预览")}
            </span>
          </div>
        </div>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <span>
            工作空间 <ChevronRight size={14} aria-hidden="true" />{" "}
            {activePage.label}
          </span>
          <Badge good={!!snapshot?.device?.status}>
            {snapshot
              ? deviceConnectionLabel(snapshot)
              : native
                ? "连接本机服务…"
                : "仅界面预览"}
          </Badge>
        </header>
        <main id="content">
          <div className="page-heading">
            <div>
              <h1 ref={heading} tabIndex={-1}>
                {activePage.label}
              </h1>
              <p>{activePage.description}</p>
            </div>
            <span className="preview-chip">RUST</span>
          </div>
          {error && (
            <div className="message error" role="alert">
              <span>{error}</span>
              <button aria-label="关闭错误提示" onClick={() => setError("")}>
                <X size={18} />
              </button>
            </div>
          )}
          {!native && (
            <div className="message">
              当前是浏览器中的设计预览。保存设置和桌面字幕需要打开原生客户端。
            </div>
          )}

          {page === "voice" && (
            <>
              <section aria-labelledby="engine-title" className="voice-overview">
                <div className="section-heading"><h2 id="engine-title">语音识别</h2><span>选择后自动生效 · 托盘也可切换</span></div>
                <ProviderPicker value={draft.provider} onChange={provider=>patch({provider})} windows={!snapshot||snapshot.platform==="windows"}/>
                <div className="voice-quickbar">
                  <label>Profile<select aria-label="当前 Profile" value={draft.activeProfile} onChange={e=>patch({activeProfile:e.target.value})}>{draft.profiles.map(p=><option value={p.id} key={p.id}>{p.name}</option>)}</select></label>
                  <label>触发<select aria-label="语音触发方式" value={draft.triggerMode} onChange={e=>patch({triggerMode:e.target.value as Settings["triggerMode"]})}><option value="hold">按住说话</option><option value="toggle">按一下开始 / 停止</option></select></label>
                  <button className="secondary" disabled={busy||!snapshot?.nativeKeyTestSupported} aria-pressed={snapshot?.nativeKeyTestEnabled??false} onClick={keyTest}>{snapshot?.nativeKeyTestEnabled?"语音键已开启":"启用语音键"}</button>
                </div>
                <p className="hint">语音键监听默认开启，手动关闭后会记住。监听按键不会自动录音，USB 和蓝牙输入均可使用。</p>
              </section>
              <VoiceControls snapshot={snapshot} draft={draft} patch={patch} changed={changed} fail={setError}/>
              <section className="surface compact-captions">
                <div className="section-heading"><h2><Subtitles size={18} aria-hidden="true"/>桌面字幕</h2><label className="switch-label"><input type="checkbox" checked={draft.captionsEnabled} onChange={e=>patch({captionsEnabled:e.target.checked})}/>{draft.captionsEnabled?"已开启":"已关闭"}</label></div>
                <p className="section-description">{draft.provider==="wechat"||draft.provider==="windows-native"?"AhaKey 实时字幕用于本地 / 豆包识别；当前输入法使用自己的语音浮窗。":"跟随目标输入窗口所在屏幕，显示在任务栏上方，不抢输入焦点。"}</p>
                {(draft.provider==="local"||draft.provider==="doubao"||caption.text)&&<div className="caption-example"><div><AudioLines size={16} aria-hidden="true"/>{phaseLabel(caption.phase)}</div><p role="status" aria-live="polite">{caption.text||"语音开始后在这里查看文字，也可先预览浮窗位置。"}</p></div>}
                <div className="button-row"><button className="secondary" disabled={!snapshot||!draft.captionsEnabled||changed||snapshot.speech.recording} onClick={()=>test(true)}>预览当前位置</button><button className="text-button" disabled={!snapshot} onClick={()=>invoke("dismiss_caption").catch(e=>setError(String(e)))}>收起浮窗</button></div>
                <details className="compact-details"><summary>多屏显示说明</summary><p>语音开始时使用捕获的目标窗口定位，后续字幕更新继续跟随该窗口。这里的预览在设置窗口所在屏幕；托盘预览优先使用最近的工作窗口，无目标时使用鼠标屏幕。微信 / Windows 自带浮窗由各自输入法控制。</p></details>
              </section>
            </>
          )}

          {page === "device" && <div className="device-page">
            <DeviceInformation snapshot={snapshot} />
            <section className="surface device-key-entry" aria-labelledby="device-key-entry-title">
              <div><h2 id="device-key-entry-title">实体按键</h2><p className="section-description">分别设置四个按键的语音、快捷键或禁用动作。</p></div>
              <button className="secondary" onClick={()=>{setPage("hooks");requestAnimationFrame(()=>{const heading=document.getElementById("four-keys-title");heading?.scrollIntoView({block:"start"});heading?.focus({preventScroll:true});});}}>定义四个实体按键</button>
            </section>
            <DevicePanel snapshot={snapshot} draft={draft} patch={patch} changed={changed} fail={setError} />
            <RoutingPanel ready={snapshot?.bleReady ?? false} usbSupported={snapshot?.platform === "windows"} generation={snapshot?.ble?.generation ?? 0} />
          </div>}

          {page === "hooks" && (
            <>
              <section className="surface">
                <div className="section-heading">
                  <h2>应用配置</h2>
                  <Badge>本机偏好</Badge>
                </div>
                <p className="section-description">
                  区分终端与桌面应用。保存后可将映射写入设备；这是按键配置，不会自动聚焦应用或批准操作。
                </p>
                <div className="profile-grid">
                  {draft.profiles.map((profile, index) => (
                    <button
                      key={profile.id}
                      aria-pressed={profile.id === draft.activeProfile}
                      className={`profile-card ${profile.id === draft.activeProfile ? "chosen" : ""}`}
                      onClick={() => patch({ activeProfile: profile.id })}
                    >
                      <span className="profile-number">0{index + 1}</span>
                      {profile.id.includes("desktop") ||
                      profile.id === "chatgpt-app" ? (
                        <Monitor size={22} aria-hidden="true" />
                      ) : (
                        <Command size={22} aria-hidden="true" />
                      )}
                      <strong>{profile.name}</strong>
                      <span>
                        {profile.id.includes("desktop") ||
                        profile.id === "chatgpt-app"
                          ? "桌面应用"
                          : "终端应用"}
                      </span>
                    </button>
                  ))}
                </div>
                <p className="hint">选择模式后，在下面逐一编辑四个按键；本机保存和写入键盘是两个明确步骤。</p>
              </section>
              <FourKeysPanel snapshot={snapshot} draft={draft} patch={patch} changed={changed} fail={setError} />
              <HookPanel snapshot={snapshot} draft={draft} patch={patch} changed={changed} fail={setError} />
            </>
          )}

          {page === "display" && <DisplayPanel />}
          {page === "settings" && (
            <>
              <section className="surface">
                <h2>
                  <SlidersHorizontal size={19} aria-hidden="true" />
                  输入偏好
                </h2>
                <div className="setting-row">
                  <div>
                    <strong>按键触发方式</strong>
                    <p>原生 F17 / F18 语音键；微信模式由客户端发送开始和结束快捷键。</p>
                  </div>
                  <select
                    aria-label="按键触发方式"
                    value={draft.triggerMode}
                    onChange={(e) =>
                      patch({
                        triggerMode: e.target.value as Settings["triggerMode"],
                      })
                    }
                  >
                    <option value="hold">按住说话</option>
                    <option value="toggle">按一下开始 / 停止</option>
                  </select>
                </div>
                <div className="setting-row">
                  <div>
                    <strong>桌面字幕</strong>
                    <p>在目标屏幕底部显示，不获取输入焦点。</p>
                  </div>
                  <label className="switch-label">
                    <input
                      type="checkbox"
                      checked={draft.captionsEnabled}
                      onChange={(e) =>
                        patch({ captionsEnabled: e.target.checked })
                      }
                    />
                    {draft.captionsEnabled ? "已开启" : "已关闭"}
                  </label>
                </div>
                <div className="setting-row">
                  <div>
                    <strong>字幕与任务栏的距离</strong>
                    <p>以目标屏幕的缩放比例换算位置。</p>
                  </div>
                  <label className="number-label">
                    <input
                      aria-label="字幕底部间距"
                      type="number"
                      min="8"
                      max="160"
                      value={draft.captionBottomOffset}
                      onChange={(e) =>
                        patch({ captionBottomOffset: Number(e.target.value) })
                      }
                    />
                    px
                  </label>
                </div>
              </section>
              <EnginePanel snapshot={snapshot} draft={draft} patch={patch} changed={changed} fail={setError} />
              <section className="surface">
                <h2>关于此预览版</h2>
                <dl className="about-list">
                  <div>
                    <dt>运行环境</dt>
                    <dd>
                      {snapshot?.platform ?? "浏览器预览"} · Rust + Tauri 2 +
                      React
                    </dd>
                  </div>
                  <div>
                    <dt>配置文件</dt>
                    <dd className="file-path">
                      {snapshot?.settingsPath ?? "仅原生客户端可保存"}
                    </dd>
                  </div>
                  <div>
                    <dt>目标屏幕定位</dt>
                    <dd>
                      {snapshot?.foregroundCaptionSupported
                        ? "Windows 前台窗口所在屏幕"
                        : "此平台暂使用主屏幕，前台适配器待实现"}
                    </dd>
                  </div>
                  <div>
                    <dt>发行通道</dt>
                    <dd>开发预览 · 独立于 JavaFX 日常版</dd>
                  </div>
                </dl>
              </section>
            </>
          )}
        </main>
        <footer className="save-bar">
          <div role="status" aria-live="polite">
            {busy ? "正在保存并应用…" : changed ? saveFailed ? "保存失败，当前修改尚未生效" : "等待自动应用…" : notice ? (
              <>
                <Check size={16} aria-hidden="true" />
                {notice}
              </>
            ) : (
              <>
                <ShieldCheck size={16} aria-hidden="true" />
                设置仅保存在此设备
              </>
            )}
          </div>
          <button
            className="primary"
            disabled={!changed || busy || !!snapshot?.settingsError}
            onClick={save}
          >
            {busy ? "正在应用…" : saveFailed ? "重试保存" : "立即应用"}
          </button>
        </footer>
      </div>
    </div>
  );
}

const isCaption = new URLSearchParams(location.search).has("caption");
document.documentElement.classList.toggle("caption-page", isCaption);
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    {isCaption ? <CaptionWindow /> : <App />}
  </React.StrictMode>,
);
