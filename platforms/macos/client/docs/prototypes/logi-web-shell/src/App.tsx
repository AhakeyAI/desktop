import { ClaudeCode, Codex, Cursor } from "@lobehub/icons";
import {
  ArrowLeft,
  Battery,
  Bluetooth,
  Bot,
  Check,
  ChevronDown,
  ChevronRight,
  CircleAlert,
  Cpu,
  Download,
  Keyboard,
  LayoutGrid,
  Lightbulb,
  Mic,
  Moon,
  Plus,
  RefreshCw,
  Settings,
  SlidersHorizontal,
  Sun,
  ToggleLeft,
  UserRound,
  WandSparkles,
  Wifi,
} from "lucide-react";
import type { ComponentType, ElementType, ReactNode, SVGProps } from "react";
import { useEffect, useState } from "react";

type Page = "home" | "add-device" | "studio" | "settings";
type StudioSection = "keys" | "oled" | "lights" | "approval" | "agent" | "voice" | "device";
type Platform = "claude" | "cursor" | "codex";
type DeviceState = "noDevice" | "scanning" | "connected" | "disconnected" | "permissionRequired";
type ControlState = "runtimeOwnerAgent" | "configOwnerStudio" | "handoffPending" | "handoffFailed";
type SyncState = "clean" | "dirty" | "syncing" | "synced" | "syncFailed";
type Theme = "light" | "dark";
type LayoutMode = "desktop" | "compactDesktop" | "mobileOverlay";
type SettingsTab = "general" | "notifications" | "support" | "service" | "privacy";
type Hotspot = "key1" | "key2" | "key3" | "key4" | "oled" | "lightbar" | "dial";
type HardwareSection = "keys" | "oled" | "lights" | "approval";
type PermissionState = "ok" | "missing";
type ActionMode = "shortcut" | "macro";

type VoiceKeyConfig = {
  presetName: string;
  permission: PermissionState;
  triggerKey: string;
  descriptionLabel: string;
};

type ActionKeyConfig = {
  mode: ActionMode;
  shortcut: string;
  descriptionLabel: string;
  macroSteps: string[];
};

type OledConfig = {
  asset: string;
  fps: number;
  preview: string;
  saved: boolean;
};

type LightsConfig = {
  summary: string;
  previewState: string;
  mappings: Array<{ state: string; effect: string }>;
};

type ApprovalConfig = {
  position: "自动批准" | "手动批准";
  platformSummary: string;
};

type PlatformDraft = {
  key1: VoiceKeyConfig;
  key2: ActionKeyConfig;
  key3: ActionKeyConfig;
  key4: ActionKeyConfig;
  oled: OledConfig;
  lights: LightsConfig;
  approval: ApprovalConfig;
};

type PlatformIcon = ComponentType<SVGProps<SVGSVGElement>>;

const platforms: Array<{ id: Platform; label: string; Icon: PlatformIcon }> = [
  { id: "claude", label: "Claude Code", Icon: ClaudeCode },
  { id: "cursor", label: "Cursor", Icon: Cursor },
  { id: "codex", label: "Codex", Icon: Codex },
];

const hotspots: Array<{
  id: Hotspot;
  label: string;
  x: number;
  y: number;
  section: StudioSection;
  shortcut: string;
}> = [
  { id: "key1", label: "Ask", x: 18, y: 42, section: "keys", shortcut: "Cmd Shift A" },
  { id: "key2", label: "Plan", x: 38, y: 42, section: "keys", shortcut: "Cmd Shift P" },
  { id: "key3", label: "Run", x: 58, y: 42, section: "keys", shortcut: "Cmd Shift R" },
  { id: "key4", label: "Ship", x: 78, y: 42, section: "keys", shortcut: "Cmd Shift S" },
  { id: "oled", label: "OLED", x: 49, y: 17, section: "oled", shortcut: "状态摘要" },
  { id: "lightbar", label: "Light bar", x: 50, y: 83, section: "lights", shortcut: "运行反馈" },
  { id: "dial", label: "Approval", x: 92, y: 61, section: "approval", shortcut: "批准 / 拒绝" },
];

const hardwareSections: HardwareSection[] = ["keys", "oled", "lights", "approval"];

const sectionHotspots: Record<HardwareSection, Hotspot[]> = {
  keys: ["key1", "key2", "key3", "key4"],
  oled: ["oled"],
  lights: ["lightbar"],
  approval: ["dial"],
};

const partMeta: Record<
  Hotspot,
  {
    title: string;
    subtitle: string;
    section: HardwareSection;
  }
> = {
  key1: {
    title: "Key 1",
    subtitle: "语音",
    section: "keys",
  },
  key2: {
    title: "Key 2",
    subtitle: "批准",
    section: "keys",
  },
  key3: {
    title: "Key 3",
    subtitle: "拒绝",
    section: "keys",
  },
  key4: {
    title: "Key 4",
    subtitle: "提交",
    section: "keys",
  },
  oled: {
    title: "OLED",
    subtitle: "显示",
    section: "oled",
  },
  lightbar: {
    title: "灯条",
    subtitle: "状态",
    section: "lights",
  },
  dial: {
    title: "拨杆",
    subtitle: "档位",
    section: "approval",
  },
};

const sectionMeta: Record<HardwareSection, { title: string }> = {
  keys: {
    title: "按键",
  },
  oled: {
    title: "OLED",
  },
  lights: {
    title: "灯条",
  },
  approval: {
    title: "拨杆",
  },
};

function getLayoutMode(width: number): LayoutMode {
  if (width < 900) return "mobileOverlay";
  if (width < 1280) return "compactDesktop";
  return "desktop";
}

const initialPlatformDrafts: Record<Platform, PlatformDraft> = {
  claude: {
    key1: { presetName: "macOS 原生", permission: "ok", triggerKey: "F18", descriptionLabel: "Record" },
    key2: { mode: "shortcut", shortcut: "F19", descriptionLabel: "Yes", macroSteps: ["downKey Y", "delay 30ms", "upKey Y"] },
    key3: { mode: "shortcut", shortcut: "Escape", descriptionLabel: "No", macroSteps: ["downKey Escape", "delay 30ms", "upKey Escape"] },
    key4: { mode: "macro", shortcut: "Enter", descriptionLabel: "Submit", macroSteps: ["downKey Cmd", "downKey Enter", "upAllKeys"] },
    oled: { asset: "Review queue", fps: 12, preview: "Review queue", saved: false },
    lights: {
      summary: "灯条效果由固件根据键盘状态自动驱动。",
      previewState: "工具调用前",
      mappings: [
        { state: "会话开始", effect: "蓝色呼吸" },
        { state: "工具调用前", effect: "黄色常亮" },
        { state: "工具调用后", effect: "绿色闪烁" },
        { state: "任务完成", effect: "绿色常亮" },
      ],
    },
    approval: {
      position: "手动批准",
      platformSummary: "当前模式下的工具调用需要物理按下 Key 2 确认。",
    },
  },
  cursor: {
    key1: { presetName: "Typeless", permission: "missing", triggerKey: "F18", descriptionLabel: "Dictate" },
    key2: { mode: "shortcut", shortcut: "Cmd .", descriptionLabel: "Accept", macroSteps: ["downKey Cmd", "downKey .", "upAllKeys"] },
    key3: { mode: "macro", shortcut: "Cmd Backspace", descriptionLabel: "Reject", macroSteps: ["downKey Cmd", "downKey Backspace", "upAllKeys"] },
    key4: { mode: "shortcut", shortcut: "Enter", descriptionLabel: "Submit", macroSteps: ["downKey Shift", "downKey Enter", "upAllKeys"] },
    oled: { asset: "Inline draft", fps: 10, preview: "Inline draft", saved: true },
    lights: {
      summary: "光效会跟随编辑器状态变化，当前只开放预览。",
      previewState: "会话开始",
      mappings: [
        { state: "会话开始", effect: "蓝色呼吸" },
        { state: "权限请求", effect: "橙色常亮" },
        { state: "任务完成", effect: "绿色常亮" },
        { state: "停止", effect: "红色常亮" },
      ],
    },
    approval: {
      position: "自动批准",
      platformSummary: "当前模式下默认自动批准，工具调用无需物理确认。",
    },
  },
  codex: {
    key1: { presetName: "微信", permission: "ok", triggerKey: "F18", descriptionLabel: "Voice" },
    key2: { mode: "shortcut", shortcut: "Cmd Shift P", descriptionLabel: "Approve", macroSteps: ["downKey Cmd", "downKey Shift", "downKey P", "upAllKeys"] },
    key3: { mode: "shortcut", shortcut: "Cmd Shift R", descriptionLabel: "Reject", macroSteps: ["downKey Cmd", "downKey Shift", "downKey R", "upAllKeys"] },
    key4: { mode: "macro", shortcut: "Cmd Shift S", descriptionLabel: "Submit", macroSteps: ["downKey Cmd", "downKey Shift", "downKey S", "upAllKeys"] },
    oled: { asset: "Plan mode", fps: 8, preview: "Plan mode", saved: false },
    lights: {
      summary: "运行与确认状态由固件自动驱动，自定义灯效将在后续版本支持。",
      previewState: "任务完成",
      mappings: [
        { state: "运行中", effect: "淡蓝常亮" },
        { state: "等待批准", effect: "橙色脉冲" },
        { state: "任务完成", effect: "绿色常亮" },
        { state: "停止", effect: "红色常亮" },
      ],
    },
    approval: {
      position: "手动批准",
      platformSummary: "当前模式下保持手动批准，确保关键提交前需要实体确认。",
    },
  },
};

const settingsTabs: Array<{ id: SettingsTab; label: string }> = [
  { id: "general", label: "通用" },
  { id: "support", label: "反馈与支持" },
  { id: "service", label: "AhaKey 服务" },
  { id: "notifications", label: "通知" },
  { id: "privacy", label: "隐私与数据" },
];

const storageKey = "ahakey_logi_web_shell_theme";

export default function App() {
  const [page, setPage] = useState<Page>("home");
  const [theme, setTheme] = useState<Theme>(() => {
    const stored = localStorage.getItem(storageKey);
    return stored === "dark" || stored === "light" ? stored : "light";
  });
  const [deviceState, setDeviceState] = useState<DeviceState>("noDevice");
  const [controlState, setControlState] = useState<ControlState>("runtimeOwnerAgent");
  const [syncState, setSyncState] = useState<SyncState>("dirty");
  const [platform, setPlatform] = useState<Platform>("codex");
  const [studioSection, setStudioSection] = useState<StudioSection>("keys");
  const [selectedHotspot, setSelectedHotspot] = useState<Hotspot | null>(null);
  const [settingsTab, setSettingsTab] = useState<SettingsTab>("general");
  const [showMockPanel, setShowMockPanel] = useState(false);
  const [platformDrafts, setPlatformDrafts] = useState<Record<Platform, PlatformDraft>>(initialPlatformDrafts);

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem(storageKey, theme);
  }, [theme]);

  const selected = selectedHotspot ? hotspots.find((item) => item.id === selectedHotspot) ?? null : null;
  const hasDevice = deviceState !== "noDevice";
  const currentDraft = platformDrafts[platform];
  const selectedMeta = selectedHotspot ? partMeta[selectedHotspot] : null;

  const goStudio = () => {
    setDeviceState((current) => (current === "noDevice" ? "connected" : current));
    setPage("studio");
  };

  const completePairing = () => {
    setDeviceState("connected");
    setPage("studio");
  };

  const setSelectedHotspotWithRules = (hotspot: Hotspot | null) => {
    setSelectedHotspot(hotspot);
    if (hotspot) {
      setStudioSection(partMeta[hotspot].section);
    }
  };

  const setStudioSectionWithReset = (section: StudioSection) => {
    setStudioSection(section);
    if (!hardwareSections.includes(section as HardwareSection)) {
      setSelectedHotspot(null);
      return;
    }
    if (selectedHotspot && partMeta[selectedHotspot].section !== section) {
      setSelectedHotspot(null);
    }
  };

  const updatePlatformDraft = (updater: (draft: PlatformDraft) => PlatformDraft) => {
    setPlatformDrafts((current) => ({
      ...current,
      [platform]: updater(current[platform]),
    }));
  };

  return (
    <div className="app-frame">
      <MacTrafficLights />
      <main className="app-window">
        {page === "home" && (
          <HomePage
            theme={theme}
            setTheme={setTheme}
            deviceState={deviceState}
            setPage={setPage}
            goStudio={goStudio}
          />
        )}
        {page === "add-device" && (
          <AddDevicePage
            deviceState={deviceState}
            setDeviceState={setDeviceState}
            completePairing={completePairing}
            setPage={setPage}
          />
        )}
        {page === "studio" && (
          <DeviceStudioPage
            platform={platform}
            setPlatform={setPlatform}
            section={studioSection}
            setSection={setStudioSectionWithReset}
            selectedHotspot={selectedHotspot}
            setSelectedHotspot={setSelectedHotspotWithRules}
            selected={selected}
            selectedMeta={selectedMeta}
            currentDraft={currentDraft}
            updatePlatformDraft={updatePlatformDraft}
            controlState={controlState}
            syncState={syncState}
            deviceState={deviceState}
            setPage={setPage}
          />
        )}
        {page === "settings" && (
          <SettingsPage
            theme={theme}
            setTheme={setTheme}
            settingsTab={settingsTab}
            setSettingsTab={setSettingsTab}
            setPage={setPage}
          />
        )}
      </main>
      <button
        className="mock-toggle"
        data-testid="mock-toggle"
        aria-label="Review states"
        title="Review states"
        onClick={() => setShowMockPanel((value) => !value)}
      >
        <SlidersHorizontal size={15} />
      </button>
      {showMockPanel && (
        <MockStatePanel
          page={page}
          setPage={setPage}
          theme={theme}
          setTheme={setTheme}
          deviceState={deviceState}
          setDeviceState={setDeviceState}
          controlState={controlState}
          setControlState={setControlState}
          syncState={syncState}
          setSyncState={setSyncState}
          platform={platform}
          setPlatform={setPlatform}
          hasDevice={hasDevice}
        />
      )}
    </div>
  );
}

function MacTrafficLights() {
  return (
    <div className="traffic-lights" aria-hidden="true">
      <span className="traffic traffic-red" />
      <span className="traffic traffic-yellow" />
      <span className="traffic traffic-green" />
    </div>
  );
}

function TopActions({
  theme,
  setTheme,
  setPage,
  compact = false,
}: {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  setPage: (page: Page) => void;
  compact?: boolean;
}) {
  return (
    <div className="top-actions">
      {!compact && (
        <button className="text-action" onClick={() => setPage("add-device")}>
          <Plus size={19} />
          添加设备
        </button>
      )}
      <span className="top-divider" />
      <button className="icon-text-action" aria-label="同步">
        <RefreshCw size={21} />
        {!compact && "同步"}
      </button>
      <button className="icon-text-action" aria-label="快捷操作">
        <WandSparkles size={22} />
        {!compact && "快捷操作"}
      </button>
      <button className="icon-button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")} aria-label="切换主题">
        {theme === "dark" ? <Sun size={22} /> : <Moon size={22} />}
      </button>
      <span className="top-divider" />
      <button className="icon-button" aria-label="账户">
        <UserRound size={22} />
      </button>
      <button className="icon-button" onClick={() => setPage("settings")} aria-label="设置">
        <Settings size={22} />
      </button>
    </div>
  );
}

function HomePage({
  theme,
  setTheme,
  deviceState,
  setPage,
  goStudio,
}: {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  deviceState: DeviceState;
  setPage: (page: Page) => void;
  goStudio: () => void;
}) {
  const greeting = theme === "dark" ? "晚上好" : "下午好";

  return (
    <section className="home-page">
      <header className="home-topbar">
        <h1>{greeting}</h1>
        <TopActions theme={theme} setTheme={setTheme} setPage={setPage} />
      </header>
      <div className="home-stage">
        {deviceState === "noDevice" ? (
          <div className="empty-hero">
            <AhaKeyBoxIllustration />
            <button className="hero-link" onClick={() => setPage("add-device")}>
              连接设备
            </button>
          </div>
        ) : (
          <div className="device-overview">
            <DeviceHeroCard
              name="AhaKey Vibe 154F"
              status={deviceState}
              battery={82}
              onOpen={goStudio}
              featured
            />
            <aside className="device-list-panel" aria-label="设备列表">
              <DeviceListEntry
                name="AhaKey Vibe 154F"
                detail="主工作区"
                status={deviceState}
                battery={82}
                onOpen={goStudio}
              />
              <DeviceListEntry
                name="AhaKey Desk Lab"
                detail="书桌键盘"
                status={deviceState === "connected" ? "disconnected" : "connected"}
                battery={54}
                onOpen={goStudio}
              />
            </aside>
          </div>
        )}
      </div>
    </section>
  );
}

function AhaKeyBoxIllustration() {
  return (
    <div className="box-illustration" aria-label="AhaKey 设备插图">
      <div className="confetti confetti-a" />
      <div className="confetti confetti-b" />
      <div className="confetti confetti-c" />
      <div className="confetti confetti-d" />
      <div className="confetti confetti-e" />
      <div className="signal-node">
        <Bluetooth size={44} />
      </div>
      <div className="receiver-node">
        <Cpu size={35} />
      </div>
      <div className="device-box-back" />
      <div className="mini-keyboard tilted" aria-hidden="true">
        {Array.from({ length: 20 }).map((_, index) => (
          <span key={index} />
        ))}
      </div>
      <div className="mini-device-mouse" aria-hidden="true" />
      <div className="device-box">
        <span>Aha</span>
      </div>
      <div className="plant">
        <i />
        <i />
        <i />
      </div>
      <div className="hero-shadow" />
    </div>
  );
}

function DeviceHeroCard({
  name,
  status,
  battery,
  onOpen,
  featured = false,
}: {
  name: string;
  status: DeviceState;
  battery: number;
  onOpen: () => void;
  featured?: boolean;
}) {
  return (
    <button className={`device-hero ${featured ? "featured" : ""}`} onClick={onOpen}>
      <div className="keyboard-render" aria-hidden="true">
        <div className="keyboard-oled">Session ready</div>
        <div className="key-grid">
          {Array.from({ length: 40 }).map((_, index) => (
            <span key={index} className={index === 2 || index === 17 ? "key accent-key" : ""}>
              {index === 2 ? "AI" : index === 17 ? "OK" : ""}
            </span>
          ))}
        </div>
        <div className="lightbar" />
      </div>
      <div className="device-meta">
        <strong>{name}</strong>
        <span className={`battery-pill ${status === "disconnected" ? "muted" : ""}`}>
          <Battery size={15} />
          {status === "scanning" ? "扫描中" : status === "permissionRequired" ? "需要权限" : `${battery}%`}
          <Bluetooth size={14} />
        </span>
      </div>
    </button>
  );
}

function DeviceListEntry({
  name,
  detail,
  status,
  battery,
  onOpen,
}: {
  name: string;
  detail: string;
  status: DeviceState;
  battery: number;
  onOpen: () => void;
}) {
  return (
    <button className="device-list-entry" onClick={onOpen}>
      <div className="device-list-copy">
        <strong>{name}</strong>
        <span>{detail}</span>
      </div>
      <div className="device-list-meta">
        <span className={`device-list-status ${status}`}>{homeDeviceStatusLabel(status)}</span>
        <span>{battery}%</span>
      </div>
    </button>
  );
}

function AddDevicePage({
  deviceState,
  setDeviceState,
  completePairing,
  setPage,
}: {
  deviceState: DeviceState;
  setDeviceState: (state: DeviceState) => void;
  completePairing: () => void;
  setPage: (page: Page) => void;
}) {
  const scanning = deviceState === "scanning";
  const needsPermission = deviceState === "permissionRequired";
  const savedOffline = deviceState === "disconnected";
  const showDiscoveredDevice = scanning || deviceState === "connected";

  const helper = {
    noDevice: "将设备放在附近后开始扫描。",
    scanning: "正在寻找附近的 AhaKey。",
    connected: "设备已准备好，可以进入工作区。",
    disconnected: "已保存的设备当前不在线。",
    permissionRequired: "需要允许蓝牙访问后才能继续。",
  }[deviceState];

  const connectionSubtitle = needsPermission
    ? "允许蓝牙访问"
    : scanning
      ? "正在搜索附近设备"
      : savedOffline
        ? "继续搜索已保存设备"
        : "通过蓝牙连接 AhaKey";

  return (
    <section className="add-page">
      <button className="back-button" onClick={() => setPage("home")} aria-label="返回首页">
        <ArrowLeft size={26} />
      </button>
      <div className="add-stage">
        <div className="add-intro">
          <h1>选择连接类型</h1>
          <p>{helper}</p>
        </div>
        <button
          className={`connection-card ${scanning ? "active" : ""} ${needsPermission ? "muted" : ""}`}
          onClick={() => {
            if (!needsPermission) setDeviceState("scanning");
          }}
        >
          <span className="connection-icon">
            <Bluetooth size={28} />
          </span>
          <div className="connection-copy">
            <strong>蓝牙</strong>
            <span>{connectionSubtitle}</span>
          </div>
          {scanning ? <RefreshCw size={22} /> : <ChevronRight size={26} />}
        </button>
        {needsPermission && (
          <div className="permission-note">
            <CircleAlert size={18} />
            <div>
              <strong>需要蓝牙权限</strong>
              <span>允许后即可继续搜索设备。</span>
            </div>
          </div>
        )}
        {savedOffline && !scanning && !needsPermission && (
          <div className="scan-status muted">
            <Bluetooth size={16} />
            <span>已保存的设备当前不在线</span>
          </div>
        )}
        {showDiscoveredDevice && (
          <div className="scan-result-block">
            <div className="scan-status">
              <Wifi size={16} />
              <span>附近发现 1 台设备</span>
            </div>
            <button className="found-device-row" data-testid="pairing-success" onClick={completePairing}>
              <span className="found-device-icon">
                <Keyboard size={18} />
              </span>
              <div className="found-device-copy">
                <strong>AhaKey Vibe 154F</strong>
                <span>低延迟蓝牙</span>
              </div>
              <div className="found-device-meta">
                <span>82%</span>
                <ChevronRight size={20} />
              </div>
            </button>
          </div>
        )}
      </div>
    </section>
  );
}

function DeviceStudioPage({
  platform,
  setPlatform,
  section,
  setSection,
  selectedHotspot,
  setSelectedHotspot,
  selected,
  selectedMeta,
  currentDraft,
  updatePlatformDraft,
  controlState,
  syncState,
  deviceState,
  setPage,
}: {
  platform: Platform;
  setPlatform: (platform: Platform) => void;
  section: StudioSection;
  setSection: (section: StudioSection) => void;
  selectedHotspot: Hotspot | null;
  setSelectedHotspot: (hotspot: Hotspot | null) => void;
  selected: (typeof hotspots)[number] | null;
  selectedMeta: (typeof partMeta)[Hotspot] | null;
  currentDraft: PlatformDraft;
  updatePlatformDraft: (updater: (draft: PlatformDraft) => PlatformDraft) => void;
  controlState: ControlState;
  syncState: SyncState;
  deviceState: DeviceState;
  setPage: (page: Page) => void;
}) {
  const [layoutMode, setLayoutMode] = useState<LayoutMode>(() =>
    getLayoutMode(typeof window === "undefined" ? 1440 : window.innerWidth),
  );
  const hardwareSection = section === "keys" || section === "oled" || section === "lights" || section === "approval";
  const currentHardwareSection = section as HardwareSection;
  const activeParts = sectionHotspots[currentHardwareSection] ?? [];
  const inspectorOpen = hardwareSection && selectedHotspot !== null;
  const sidebarCollapsed =
    hardwareSection &&
    (layoutMode === "compactDesktop" || (layoutMode === "desktop" && inspectorOpen));

  useEffect(() => {
    const updateLayoutMode = () => setLayoutMode(getLayoutMode(window.innerWidth));
    updateLayoutMode();
    window.addEventListener("resize", updateLayoutMode);
    return () => window.removeEventListener("resize", updateLayoutMode);
  }, []);

  return (
    <section className={`studio-page layout-${layoutMode}`}>
      <header className="studio-topbar">
        <button className="back-title" onClick={() => setPage("home")}>
          <ArrowLeft size={23} />
          <span>
            AhaKey Studio
            <small>vibe code 154F</small>
          </span>
        </button>
        <PlatformSwitcher platform={platform} setPlatform={setPlatform} />
      </header>
      <div
        className={`studio-shell layout-${layoutMode} ${sidebarCollapsed ? "sidebar-collapsed" : ""} ${inspectorOpen ? "inspector-open" : ""}`}
      >
        <StudioSidebar
          section={section}
          setSection={setSection}
          collapsed={sidebarCollapsed}
        />
        <main className={`studio-main ${hardwareSection ? "hardware-layout" : "two-col"} ${inspectorOpen ? "inspector-open" : ""}`}>
          {hardwareSection ? (
            <>
              <StudioCanvas
                section={currentHardwareSection}
                selectedHotspot={selectedHotspot}
                setSelectedHotspot={setSelectedHotspot}
                selected={selected}
                selectedMeta={selectedMeta}
                syncState={syncState}
                activeParts={activeParts}
              />
              {selected && selectedMeta ? (
                <StudioInspector
                  selected={selected}
                  selectedMeta={selectedMeta}
                  currentDraft={currentDraft}
                  controlState={controlState}
                  syncState={syncState}
                  setSection={setSection}
                  updatePlatformDraft={updatePlatformDraft}
                  layoutMode={layoutMode}
                />
              ) : null}
            </>
          ) : (
            <>
              {section === "agent" && <ServicePage controlState={controlState} />}
              {section === "voice" && <VoicePage currentDraft={currentDraft} />}
              {section === "device" && <DeviceInfoPanel deviceState={deviceState} />}
            </>
          )}
        </main>
      </div>
    </section>
  );
}

function PlatformSwitcher({
  platform,
  setPlatform,
}: {
  platform: Platform;
  setPlatform: (platform: Platform) => void;
}) {
  return (
    <div className="platform-switcher" aria-label="平台切换器">
      {platforms.map((item) => (
        <button
          key={item.id}
          className={item.id === platform ? "active" : ""}
          onClick={() => setPlatform(item.id)}
          aria-label={item.label}
          title={item.label}
        >
          <span className="platform-logo" aria-hidden="true">
            <item.Icon width={18} height={18} />
          </span>
        </button>
      ))}
    </div>
  );
}

function StudioSidebar({
  section,
  setSection,
  collapsed,
}: {
  section: StudioSection;
  setSection: (section: StudioSection) => void;
  collapsed: boolean;
}) {
  const items: Array<{ id: StudioSection; label: string; icon: ElementType; group?: "software" }> = [
    { id: "keys", label: "按键", icon: Keyboard },
    { id: "oled", label: "OLED", icon: LayoutGrid },
    { id: "lights", label: "灯条", icon: Lightbulb },
    { id: "approval", label: "拨杆", icon: ToggleLeft },
    { id: "agent", label: "后台服务", icon: Bot, group: "software" },
    { id: "voice", label: "语音", icon: Mic, group: "software" },
    { id: "device", label: "设备信息", icon: Cpu, group: "software" },
  ];

  return (
    <aside className={`studio-sidebar ${collapsed ? "collapsed" : ""}`}>
      <div className="nav-group">
        {items.slice(0, 4).map((item) => (
          <NavItem key={item.id} item={item} active={section === item.id} collapsed={collapsed} onClick={() => setSection(item.id)} />
        ))}
      </div>
      <div className="nav-separator" />
      <div className="nav-group">
        {items.slice(4).map((item) => (
          <NavItem key={item.id} item={item} active={section === item.id} collapsed={collapsed} onClick={() => setSection(item.id)} />
        ))}
      </div>
    </aside>
  );
}

function NavItem({
  item,
  active,
  collapsed,
  onClick,
}: {
  item: { label: string; icon: ElementType };
  active: boolean;
  collapsed: boolean;
  onClick: () => void;
}) {
  const Icon = item.icon;
  return (
    <button
      className={`nav-item ${active ? "active" : ""}`}
      onClick={onClick}
      aria-label={item.label}
      title={item.label}
    >
      <span>
        <Icon size={16} />
      </span>
      {!collapsed && <span className="nav-item-label">{item.label}</span>}
    </button>
  );
}

function StudioCanvas({
  section,
  selectedHotspot,
  setSelectedHotspot,
  selected,
  selectedMeta,
  syncState,
  activeParts,
}: {
  section: HardwareSection;
  selectedHotspot: Hotspot | null;
  setSelectedHotspot: (hotspot: Hotspot | null) => void;
  selected: (typeof hotspots)[number] | null;
  selectedMeta: (typeof partMeta)[Hotspot] | null;
  syncState: SyncState;
  activeParts: Hotspot[];
}) {
  const meta = sectionMeta[section];

  return (
    <section className="canvas-card">
      <div className="canvas-head">
        <strong>{meta.title}</strong>
        <span className={`sync-chip ${syncState}`}>{syncLabel(syncState)}</span>
      </div>
      <div className={`canvas-stage ${selectedHotspot ? "focused" : ""}`}>
        <div className="twin-board">
          <div className="board-oled">Session ready</div>
          <div className="board-keys">
            {Array.from({ length: 32 }).map((_, index) => (
              <span key={index} className={index % 7 === 0 ? "wide" : ""} />
            ))}
          </div>
          <div className="board-lightbar" />
          {hotspots.filter((hotspot) => activeParts.includes(hotspot.id)).map((hotspot) => (
            <button
              key={hotspot.id}
              className={`hotspot ${selectedHotspot === hotspot.id ? "active" : ""}`}
              style={{ left: `${hotspot.x}%`, top: `${hotspot.y}%` }}
              onClick={() => setSelectedHotspot(hotspot.id)}
              aria-label={hotspot.label}
            >
              <span />
            </button>
          ))}
          {selected && selectedMeta && (
            <div className="callout" style={{ left: `${selected.x + 5}%`, top: `${selected.y - 8}%` }}>
              <strong>{selectedMeta.title}</strong>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}

function StudioInspector({
  selected,
  selectedMeta,
  currentDraft,
  controlState,
  syncState,
  setSection,
  updatePlatformDraft,
  layoutMode,
}: {
  selected: (typeof hotspots)[number];
  selectedMeta: (typeof partMeta)[Hotspot];
  currentDraft: PlatformDraft;
  controlState: ControlState;
  syncState: SyncState;
  setSection: (section: StudioSection) => void;
  updatePlatformDraft: (updater: (draft: PlatformDraft) => PlatformDraft) => void;
  layoutMode: LayoutMode;
}) {
  const writable = controlState === "configOwnerStudio";
  const showFooter =
    writable &&
    syncState !== "clean" &&
    (selected.id === "key1" || selected.id === "key2" || selected.id === "key3" || selected.id === "key4");

  return (
    <aside className={`inspector ${layoutMode === "mobileOverlay" ? "overlay" : ""}`}>
      <div className="inspector-scroll">
        <div className="inspector-title">
          <h2>{selectedMeta.title}</h2>
        </div>
        {!writable && (
          <div className="notice-panel">
            <CircleAlert size={18} />
            当前为{controlLabel(controlState)}，暂不可写入。
          </div>
        )}
        {selected.id === "key1" && (
          <VoiceKeyInspector
            config={currentDraft.key1}
            onDescriptionChange={(value) =>
              updatePlatformDraft((draft) => ({
                ...draft,
                key1: { ...draft.key1, descriptionLabel: value },
              }))
            }
            onGoVoice={() => setSection("voice")}
          />
        )}
        {selected.id === "key2" && (
          <ActionKeyInspector
            config={currentDraft.key2}
            onChange={(next) => updatePlatformDraft((draft) => ({ ...draft, key2: next }))}
          />
        )}
        {selected.id === "key3" && (
          <ActionKeyInspector
            config={currentDraft.key3}
            onChange={(next) => updatePlatformDraft((draft) => ({ ...draft, key3: next }))}
          />
        )}
        {selected.id === "key4" && (
          <ActionKeyInspector
            config={currentDraft.key4}
            onChange={(next) => updatePlatformDraft((draft) => ({ ...draft, key4: next }))}
          />
        )}
        {selected.id === "oled" && (
          <OledInspector
            config={currentDraft.oled}
            onSave={() =>
              updatePlatformDraft((draft) => ({
                ...draft,
                oled: { ...draft.oled, saved: true },
              }))
            }
          />
        )}
        {selected.id === "lightbar" && <LightsInspector config={currentDraft.lights} />}
        {selected.id === "dial" && (
          <ApprovalInspector
            config={currentDraft.approval}
            onGoService={() => setSection("agent")}
          />
        )}
      </div>
      {showFooter && (
        <div className="inspector-footer">
          <span className={`meta-badge ${syncState}`}>{syncLabel(syncState)}</span>
          <button className="primary-button">
            <Download size={16} />
            同步到键盘
          </button>
        </div>
      )}
    </aside>
  );
}

function ServicePage({ controlState }: { controlState: ControlState }) {
  return (
    <section className="secondary-pane">
      <h2>后台服务</h2>
      <p>连接、控制权与覆盖状态。</p>
      <div className="panel-grid">
        <div className="panel">
          <h3>状态</h3>
          <div className="option-row">
            <span>当前模式</span>
            <strong>{controlLabel(controlState)}</strong>
          </div>
          <div className="option-row">
            <span>后台服务</span>
            <strong>运行中</strong>
          </div>
        </div>
        <div className="panel">
          <h3>覆盖</h3>
          <div className="option-row">
            <span>已接入应用</span>
            <strong>3 个工作区</strong>
          </div>
          <div className="option-row">
            <span>蓝牙连接</span>
            <strong>稳定</strong>
          </div>
        </div>
      </div>
    </section>
  );
}

function VoicePage({
  currentDraft,
}: {
  currentDraft: PlatformDraft;
}) {
  return (
    <section className="secondary-pane">
      <h2>语音设置</h2>
      <p>查看预设与权限。</p>
      <div className="panel">
        <h3>当前状态</h3>
        <div className="option-row">
          <span>麦克风</span>
          <strong>{currentDraft.key1.permission === "ok" ? "已允许" : "缺少权限"}</strong>
        </div>
        <div className="option-row">
          <span>当前预设</span>
          <strong>{currentDraft.key1.presetName}</strong>
        </div>
      </div>
      <div className="panel">
        <h3>路由</h3>
        <p>输入监控、辅助功能、麦克风与语音识别。</p>
      </div>
    </section>
  );
}

function DeviceInfoPanel({ deviceState }: { deviceState: DeviceState }) {
  return (
    <section className="secondary-pane">
      <h2>AhaKey Vibe 154F</h2>
      <p>查看连接、固件与诊断。</p>
      <div className="panel-grid">
        <div className="panel">
          <h3>连接</h3>
          <strong>{connectionLabel(deviceState)}</strong>
          <p>蓝牙 LE，信号 92%</p>
        </div>
        <div className="panel">
          <h3>固件</h3>
          <strong>0.8.2-proto</strong>
          <p>没有执行真实更新检查。</p>
        </div>
      </div>
    </section>
  );
}

function VoiceKeyInspector({
  config,
  onDescriptionChange,
  onGoVoice,
}: {
  config: VoiceKeyConfig;
  onDescriptionChange: (value: string) => void;
  onGoVoice: () => void;
}) {
  return (
    <>
      <div className="panel">
        <h3>语音</h3>
        <div className="option-row">
          <span>语音预设</span>
          <strong>{config.presetName}</strong>
        </div>
        <div className="option-row">
          <span>触发键</span>
          <strong>{config.triggerKey}</strong>
        </div>
        <div className="option-row">
          <span>权限</span>
          <strong>{config.permission === "ok" ? "正常" : "缺少权限"}</strong>
        </div>
      </div>
      <div className="panel compact-panel">
        <button className="panel-link" onClick={onGoVoice}>
          语音设置
        </button>
      </div>
      <div className="panel">
        <h3>按键描述</h3>
        <InlineTextInput value={config.descriptionLabel} onChange={onDescriptionChange} />
      </div>
    </>
  );
}

function ActionKeyInspector({
  config,
  onChange,
}: {
  config: ActionKeyConfig;
  onChange: (next: ActionKeyConfig) => void;
}) {
  return (
    <>
      <div className="panel">
        <h3>模式</h3>
        <div className="pill-row">
          <button
            className={`choice-pill ${config.mode === "shortcut" ? "active" : ""}`}
            onClick={() => onChange({ ...config, mode: "shortcut" })}
          >
            快捷键
          </button>
          <button
            className={`choice-pill ${config.mode === "macro" ? "active" : ""}`}
            onClick={() => onChange({ ...config, mode: "macro" })}
          >
            宏
          </button>
        </div>
        <div className="option-row">
          <span>快捷键绑定</span>
          <strong>{config.shortcut}</strong>
        </div>
      </div>
      <div className="panel">
        <details className="inline-expand" open={config.mode === "macro"}>
          <summary>宏编辑器</summary>
          <div className="macro-steps">
            {config.macroSteps.map((step) => (
              <div key={step} className="macro-step">
                {step}
              </div>
            ))}
          </div>
        </details>
      </div>
      <div className="panel">
        <h3>按键描述</h3>
        <InlineTextInput value={config.descriptionLabel} onChange={(value) => onChange({ ...config, descriptionLabel: value })} />
      </div>
    </>
  );
}

function OledInspector({
  config,
  onSave,
}: {
  config: OledConfig;
  onSave: () => void;
}) {
  return (
    <>
      <div className="panel">
        <h3>素材</h3>
        <div className="asset-strip">
          {["Review queue", "Inline draft", "Plan mode", "Build done"].map((asset) => (
            <button key={asset} className={`asset-chip ${config.asset === asset ? "active" : ""}`}>
              {asset}
            </button>
          ))}
        </div>
        <div className="option-row">
          <span>帧率</span>
          <strong>{config.fps} FPS</strong>
        </div>
      </div>
      <div className="panel">
        <h3>预览</h3>
        <div className="oled-preview-card">{config.preview}</div>
      </div>
      <div className="panel compact-panel">
        <button className="primary-button block-button" onClick={onSave}>
          上传并保存
        </button>
      </div>
    </>
  );
}

function LightsInspector({ config }: { config: LightsConfig }) {
  return (
    <>
      <div className="panel">
        <h3>灯效</h3>
        <p>{config.summary}</p>
      </div>
      <div className="panel">
        <h3>映射</h3>
        {config.mappings.map((mapping) => (
          <div key={mapping.state} className="option-row">
            <span>{mapping.state}</span>
            <strong>{mapping.effect}</strong>
          </div>
        ))}
      </div>
      <div className="panel compact-panel">
        <button className="secondary-button block-button">预览到设备</button>
      </div>
    </>
  );
}

function ApprovalInspector({
  config,
  onGoService,
}: {
  config: ApprovalConfig;
  onGoService: () => void;
}) {
  return (
    <>
      <div className="panel">
        <h3>档位</h3>
        <div className="option-row">
          <span>档位</span>
          <strong>{config.position}</strong>
        </div>
        <p>
          自动批准：后台服务运行时，工具调用自动确认。手动批准：每次工具调用需要物理按下 Key 2。
        </p>
      </div>
      <div className="panel">
        <p>{config.platformSummary}</p>
      </div>
      <div className="panel compact-panel">
        <button className="panel-link" onClick={onGoService}>
          后台服务
        </button>
      </div>
    </>
  );
}

function InlineTextInput({
  value,
  onChange,
}: {
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="inline-input">
      <input value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function SettingsPage({
  theme,
  setTheme,
  settingsTab,
  setSettingsTab,
  setPage,
}: {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  settingsTab: SettingsTab;
  setSettingsTab: (tab: SettingsTab) => void;
  setPage: (page: Page) => void;
}) {
  return (
    <section className="settings-page">
      <aside className="settings-sidebar">
        <button className="settings-back" onClick={() => setPage("home")}>
          <ArrowLeft size={26} />
          应用程序设置
        </button>
        <nav>
          {settingsTabs.map((tab) => (
            <button
              key={tab.id}
              className={settingsTab === tab.id ? "active" : ""}
              onClick={() => setSettingsTab(tab.id)}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </aside>
      <main className="settings-content">
        {settingsTab === "general" && <GeneralSettings theme={theme} setTheme={setTheme} />}
        {settingsTab === "notifications" && <NotificationSettings />}
        {settingsTab === "support" && <SupportSettings />}
        {settingsTab === "service" && <ServiceSettings />}
        {settingsTab === "privacy" && <PrivacySettings />}
      </main>
    </section>
  );
}

function GeneralSettings({ theme, setTheme }: { theme: Theme; setTheme: (theme: Theme) => void }) {
  return (
    <div className="settings-stack">
      <h1>常规设置</h1>
      <section>
        <h2>AhaKey Studio 原型版本 0.1.0</h2>
        <p>
          浏览器验收版本。<button className="inline-link">查看发布说明</button>
        </p>
        <button className="inline-link">检查更新</button>
      </section>
      <SettingRow title="自动安装原型更新" control={<Toggle checked />} />
      <section>
        <h2>语言</h2>
        <button className="select-button">
          使用系统语言
          <ChevronDown size={18} />
        </button>
      </section>
      <section>
        <h2>颜色主题</h2>
        <div className="theme-card-row">
          <ThemeCard label="跟随操作系统主题" active={false} onClick={() => setTheme("light")} mixed />
          <ThemeCard label="浅色主题" active={theme === "light"} onClick={() => setTheme("light")} />
          <ThemeCard label="深色主题" active={theme === "dark"} onClick={() => setTheme("dark")} dark />
        </div>
      </section>
    </div>
  );
}

function NotificationSettings() {
  return (
    <div className="settings-stack">
      <h1>通知</h1>
      <section>
        <h2>通用</h2>
        <SettingRow title="应用程序内和系统中的评分通知" control={<Toggle checked />} />
      </section>
      <section>
        <h2>叠加</h2>
        <SettingRow title="低电量通知" control={<Toggle checked />} />
        <SettingRow title="Caps lock 和 Fn 锁定通知" control={<Toggle checked />} />
        <SettingRow title="麦克风静音 / 取消静音通知" control={<Toggle checked />} />
      </section>
    </div>
  );
}

function SupportSettings() {
  return (
    <div className="settings-stack support-content">
      <h1>反馈与支持</h1>
      <section>
        <h2>一般反馈</h2>
        <p>您到目前为止对 AhaKey Studio 的体验如何？欢迎在下方分享您的想法。</p>
        <button className="inline-link">分享一般反馈</button>
      </section>
      <section>
        <h2>为您的使用体验评分</h2>
        <p>请花些时间评价一下您对本原型的使用体验。</p>
        <button className="inline-link">立即评分</button>
      </section>
      <section>
        <h2>故障排除和支持</h2>
        <p>报告问题或请求支持。</p>
        <button className="inline-link">报告问题 / 请求支持</button>
      </section>
      <section>
        <h2>蓝牙连接问题</h2>
        <p>
          如果您的设备遇到蓝牙连接问题，请选择下方列出的问题并向我们发送反馈报告。
          查看报告详情，<button className="inline-link">点击此处</button>。
        </p>
        <div className="check-list">
          <label><input type="checkbox" /> 蓝牙配对困难</label>
          <label><input type="checkbox" /> 设备频繁断开连接</label>
          <label><input type="checkbox" /> 使用蓝牙时有延迟</label>
        </div>
        <button className="text-only" disabled>发送蓝牙报告</button>
      </section>
    </div>
  );
}

function ServiceSettings() {
  return (
    <div className="settings-stack">
      <h1>AhaKey 服务</h1>
      <section>
        <h2>后台服务</h2>
        <SettingRow title="开机后自动启动后台服务" control={<Toggle checked />} />
        <SettingRow title="允许后台服务在运行中持有蓝牙连接" control={<Toggle checked />} />
      </section>
      <section>
        <h2>第三方集成</h2>
        <p>当前只展示集成状态。</p>
        <button className="inline-link">配置集成状态</button>
      </section>
    </div>
  );
}

function PrivacySettings() {
  return (
    <div className="settings-stack">
      <h1>隐私与数据</h1>
      <section>
        <h2>本地优先</h2>
        <p>当前原型只在本地保存状态。</p>
      </section>
      <SettingRow title="允许发送匿名原型反馈" control={<Toggle />} />
    </div>
  );
}

function SettingRow({ title, control }: { title: string; control: ReactNode }) {
  return (
    <div className="setting-row">
      <strong>{title}</strong>
      {control}
    </div>
  );
}

function Toggle({ checked = false }: { checked?: boolean }) {
  return (
    <span className={`toggle ${checked ? "checked" : ""}`}>
      <span />
    </span>
  );
}

function ThemeCard({
  label,
  active,
  onClick,
  dark = false,
  mixed = false,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
  dark?: boolean;
  mixed?: boolean;
}) {
  return (
    <button className={`theme-card ${active ? "active" : ""} ${dark ? "dark-preview" : ""}`} onClick={onClick}>
      <div className="theme-preview">
        <span className={mixed ? "mixed" : ""} />
        <i />
        <b />
      </div>
      <div>
        <span className="theme-check">{active ? <Check size={17} /> : null}</span>
        <strong>{label}</strong>
      </div>
    </button>
  );
}

function MockStatePanel({
  page,
  setPage,
  theme,
  setTheme,
  deviceState,
  setDeviceState,
  controlState,
  setControlState,
  syncState,
  setSyncState,
  platform,
  setPlatform,
}: {
  page: Page;
  setPage: (page: Page) => void;
  theme: Theme;
  setTheme: (theme: Theme) => void;
  deviceState: DeviceState;
  setDeviceState: (state: DeviceState) => void;
  controlState: ControlState;
  setControlState: (state: ControlState) => void;
  syncState: SyncState;
  setSyncState: (state: SyncState) => void;
  platform: Platform;
  setPlatform: (platform: Platform) => void;
  hasDevice: boolean;
}) {
  return (
    <aside className="mock-panel">
      <div>
        <strong>Review controls</strong>
        <span>Mock only</span>
      </div>
      <MockSelect label="Page" value={page} onChange={(value) => setPage(value as Page)} options={["home", "add-device", "studio", "settings"]} />
      <MockSelect label="Theme" value={theme} onChange={(value) => setTheme(value as Theme)} options={["light", "dark"]} />
      <MockSelect label="Device" value={deviceState} onChange={(value) => setDeviceState(value as DeviceState)} options={["noDevice", "scanning", "connected", "disconnected", "permissionRequired"]} />
      <MockSelect label="Control" value={controlState} onChange={(value) => setControlState(value as ControlState)} options={["runtimeOwnerAgent", "configOwnerStudio", "handoffPending", "handoffFailed"]} />
      <MockSelect label="Sync" value={syncState} onChange={(value) => setSyncState(value as SyncState)} options={["clean", "dirty", "syncing", "synced", "syncFailed"]} />
      <label className="mock-select">
        <span>Platform</span>
        <select value={platform} onChange={(event) => setPlatform(event.target.value as Platform)}>
          <option value="claude">工作区 1</option>
          <option value="cursor">工作区 2</option>
          <option value="codex">工作区 3</option>
        </select>
      </label>
    </aside>
  );
}

function MockSelect({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: string[];
  onChange: (value: string) => void;
}) {
  return (
    <label className="mock-select">
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        {options.map((option) => (
          <option key={option} value={option}>{option}</option>
        ))}
      </select>
    </label>
  );
}

function connectionLabel(state: DeviceState) {
  return {
    noDevice: "无设备",
    scanning: "扫描中",
    connected: "已连接 82%",
    disconnected: "未连接",
    permissionRequired: "需要蓝牙权限",
  }[state];
}

function homeDeviceStatusLabel(state: DeviceState) {
  return {
    noDevice: "未添加",
    scanning: "扫描中",
    connected: "已连接",
    disconnected: "离线",
    permissionRequired: "需授权",
  }[state];
}

function controlLabel(state: ControlState) {
  return {
    runtimeOwnerAgent: "运行中",
    configOwnerStudio: "配置中",
    handoffPending: "切换中",
    handoffFailed: "切换失败",
  }[state];
}

function syncLabel(state: SyncState) {
  return {
    clean: "已就绪",
    dirty: "待同步",
    syncing: "同步中",
    synced: "刚刚同步",
    syncFailed: "同步失败",
  }[state];
}
