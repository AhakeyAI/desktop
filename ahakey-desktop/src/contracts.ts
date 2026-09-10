export type Provider = "local" | "doubao" | "wechat" | "windows-native";
export type TriggerMode = "hold" | "toggle";
export type Phase = "idle" | "preview" | "listening" | "transcribing" | "final" | "error";
export interface Profile {
  id: string;
  name: string;
  accept: string;
  reject: string;
  lightEffects: number[];
  keys?: KeyBinding[];
}
export interface KeyBinding { action: "voice" | "shortcut" | "disabled"; shortcut: string; label: string }
export function effectiveKeys(profile: Profile): KeyBinding[] {
  return profile.keys?.length === 4 ? structuredClone(profile.keys) : [
    { action: "voice", shortcut: "", label: "Voice" },
    { action: "shortcut", shortcut: profile.accept, label: "Accept" },
    { action: "shortcut", shortcut: profile.reject, label: "Cancel" },
    { action: "shortcut", shortcut: "Backspace", label: "Backspace" },
  ];
}
export interface Settings {
  schemaVersion: number;
  provider: Provider;
  triggerMode: TriggerMode;
  activeProfile: string;
  captionsEnabled: boolean;
  captionBottomOffset: number;
  profiles: Profile[];
  microphone: string | null;
  savedDevice: string | null;
  cloudAppId: string;
  cloudResourceId: string;
  autoInsert: boolean;
  minimizeToTray: boolean;
  lightBrightness: number;
  voiceKeysEnabled: boolean;
}
export interface Caption {
  phase: Phase;
  text: string;
  sequence: number;
}
export interface Snapshot {
  version: string;
  platform: string;
  settings: Settings;
  settingsChangeId: string | null;
  settingsPath: string;
  settingsError: string | null;
  settingsNotice: string;
  nativeKeyTestSupported: boolean;
  nativeKeyTestEnabled: boolean;
  keyObservation: { events: number; key: string; pressed: boolean };
  keyWriteNotice: string;
  foregroundCaptionSupported: boolean;
  speechEngineReady: boolean;
  bleReady: boolean;
  device: { transport: "usb" | "ble" | null; name: string | null; status: HardwareStatus | null };
  usb: { supported: boolean; status: HardwareStatus | null; error: string | null };
  caption: Caption;
  modelInstalled: boolean;
  modelDirectory: string;
  cloudConfigured: boolean;
  autoInsertSupported: boolean;
  speech: { phase: Phase; message: string; recording: boolean };
  download: { busy: boolean; progress: number; message: string };
  bleError: string | null;
  bleRecovery: { enabled: boolean; connecting: boolean; attempt: number; retryAfterSeconds: number };
  devices: DeviceInfo[];
  ble: { generation?: number; phase: "disconnected" | "connecting" | "ready" | "error"; device: DeviceInfo | null; error: string | null;
    status: { batteryLevel: number; signal: number; firmwareMain: number; firmwareSub: number; workMode: number; lightMode: number; lightBrightness: number } | null } | null;
  hookPort: number | null;
  hookLastEvent: string | null;
}
export interface HardwareStatus { batteryLevel: number; signal: number; firmwareMain: number; firmwareSub: number; workMode: number; lightMode: number; lightBrightness: number }
export function deviceConnectionLabel(snapshot: Pick<Snapshot, "device" | "nativeKeyTestEnabled"> | null): string {
  if (!snapshot) return "连接本机服务…";
  const source=snapshot.device?.transport;
  if (!source || !snapshot.device.status) return "本机服务运行 · 等待键盘";
  return `${source === "usb" ? "USB" : "蓝牙"} 已连接 · 语音键${snapshot.nativeKeyTestEnabled ? "已开启" : "未开启"}`;
}
export interface DeviceInfo { id: string; name: string; rssi: number | null; isCandidate: boolean }
export const defaultLights = [11, 5, 1, 1, 1, 6, 6, 7, 0];

// Renderer-only preview defaults. The native process is authoritative when available.
export const previewSettings: Settings = {
  schemaVersion: 1,
  provider: "wechat",
  triggerMode: "hold",
  activeProfile: "codex-cli",
  captionsEnabled: true,
  captionBottomOffset: 20,
  microphone: null, savedDevice: null, cloudAppId: "", cloudResourceId: "volc.bigasr.sauc.duration",
  autoInsert: true, minimizeToTray: true, lightBrightness: 35,
  voiceKeysEnabled: true,
  profiles: [
    { id: "claude-code", name: "Claude Code", accept: "Y", reject: "N", lightEffects: [...defaultLights] },
    {
      id: "claude-desktop",
      name: "Claude Desktop",
      accept: "Enter",
      reject: "Escape",
      lightEffects: [...defaultLights],
    },
    { id: "codex-cli", name: "Codex CLI", accept: "Y", reject: "N", lightEffects: [...defaultLights] },
    {
      id: "chatgpt-app",
      name: "ChatGPT App",
      accept: "Enter",
      reject: "Escape",
      lightEffects: [...defaultLights],
    },
  ],
};

export function phaseLabel(phase: Phase): string {
  return {
    idle: "等待输入",
    preview: "字幕预览",
    listening: "正在聆听",
    transcribing: "正在识别",
    final: "已完成",
    error: "发生错误",
  }[phase];
}

export function acceptCaption(current: Caption, incoming: Caption): Caption {
  return incoming.sequence >= current.sequence ? incoming : current;
}

export function sameSettings(left: Settings, right: Settings): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

// A slow save must never roll back a newer edit made while IPC was in flight.
export function mergeSavedDraft(current: Settings, submitted: Settings, saved: Settings): Settings {
  return mergeIncomingDraft(current, submitted, saved);
}
export function mergeIncomingDraft(current: Settings, base: Settings, incoming: Settings): Settings {
  const next = structuredClone(current);
  for (const key of Object.keys(incoming) as (keyof Settings)[]) {
    if (JSON.stringify(current[key]) === JSON.stringify(base[key])) {
      (next as unknown as Record<string, unknown>)[key] = structuredClone(incoming[key]);
    }
  }
  next.savedDevice = incoming.savedDevice;
  next.voiceKeysEnabled = incoming.voiceKeysEnabled;
  return sameSettings(next, current) ? current : next;
}
