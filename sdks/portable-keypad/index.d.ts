/// <reference types="node" />

export type AdapterId = "keysilk_v1";

export type KeySilkActionId =
  | "key1.press"
  | "key2.press"
  | "key3.press"
  | "knob1.rotate_left"
  | "knob1.press"
  | "knob1.rotate_right"
  | "knob1.press_rotate_left"
  | "knob1.press_rotate_right";

export type BindingId =
  | "Ctrl"
  | "Shift"
  | "Alt"
  | "Win"
  | "CtrlA"
  | "CtrlC"
  | "CtrlV"
  | "CtrlX"
  | "CtrlZ"
  | "CtrlY"
  | "CtrlS"
  | "CtrlP"
  | "CtrlF"
  | "CtrlAltShiftB"
  | "CtrlAltShiftC"
  | "CtrlAltShiftD"
  | "CtrlAltShiftE"
  | "CtrlAltShiftF"
  | "CtrlAltShiftG"
  | "CtrlAltShiftH"
  | "CtrlAltShiftI"
  | "A"
  | "B"
  | "C"
  | "D"
  | "E"
  | "F"
  | "G"
  | "H"
  | "I"
  | "J"
  | "K"
  | "L"
  | "M"
  | "N"
  | "O"
  | "P"
  | "Q"
  | "R"
  | "S"
  | "T"
  | "U"
  | "V"
  | "W"
  | "X"
  | "Y"
  | "Z"
  | "Digit0"
  | "Digit1"
  | "Digit2"
  | "Digit3"
  | "Digit4"
  | "Digit5"
  | "Digit6"
  | "Digit7"
  | "Digit8"
  | "Digit9"
  | "Esc"
  | "Enter"
  | "Space"
  | "Mute"
  | "VolumeDown"
  | "VolumeUp"
  | "PlayPause"
  | "NextLayer"
  | "PreviousLayer"
  | "HostOpenUrl"
  | "HostOpenPath"
  | "MouseLeftClick"
  | "MouseRightClick"
  | "MouseMiddleClick"
  | "MouseWheelUp"
  | "MouseWheelDown"
  | "CtrlMouseWheelUp"
  | "CtrlMouseWheelDown"
  | "MacroObserved"
  | "TextObserved"
  | "OpenCalculatorObserved";

export type BindingScope = "base" | "extended";

export type HotkeyCompanionBinding =
  | "CtrlAltShiftB"
  | "CtrlAltShiftC"
  | "CtrlAltShiftD"
  | "CtrlAltShiftE"
  | "CtrlAltShiftF"
  | "CtrlAltShiftG"
  | "CtrlAltShiftH"
  | "CtrlAltShiftI";

export interface AdapterInfo {
  id: AdapterId;
  brand: string;
  vid: number;
  pid: number;
  layout: string;
  actions: KeySilkActionId[];
  bindings: BindingId[];
}

export interface KeyboardDevice {
  adapter: AdapterId;
  brand: string;
  vid: number;
  pid: number;
  path: string;
  interfaceIndex: number;
  usagePage: number;
  usage: number;
  inputReportLength: number;
  outputReportLength: number;
  featureReportLength: number;
  isConfigInterface: boolean;
}

export interface LayoutAction {
  id: KeySilkActionId | string;
  label: string;
}

export interface LayoutComponent {
  id: string;
  type: "button" | "encoder" | string;
  label: string;
  actions: LayoutAction[];
}

export interface KeyboardLayout {
  brand: string;
  model: string;
  adapter: AdapterId;
  layout: string;
  components: LayoutComponent[];
}

export interface BindingInfo {
  id: BindingId;
  label: string;
  category: "shortcut" | "basic-key" | "media" | "layer" | "host-action" | "mouse" | "mouse-wheel" | "macro" | "text" | "open-program" | string;
  verification: "hardware" | "observed" | "inferred" | string;
  aliases: string[];
}

export type CapabilityState = "done" | "observed" | "inferred" | "blocked";

export interface CapabilityFeature {
  id: string;
  label: string;
  state: CapabilityState;
  bindings?: string[];
}

export interface CapabilityInfo {
  adapter: AdapterId;
  layout: string;
  states: Record<CapabilityState, string>;
  features: CapabilityFeature[];
}

export interface ParsedRecordBinding {
  label: string;
  typeByte: number;
  code: [number, number];
  rawTail: number[];
}

export interface ParsedRecord {
  action: KeySilkActionId | string;
  offset: number | null;
  length: number;
  binding: ParsedRecordBinding | null;
}

export interface ParsedConfig {
  declaredLength: number;
  rawLength: number;
  records: ParsedRecord[];
  extendedRecords: ParsedRecord[];
}

export interface KeyboardConfig {
  adapter: AdapterId;
  device: KeyboardDevice | null;
  raw: Buffer;
  parsed: ParsedConfig;
}

export interface ImportConfigOptions {
  adapter?: AdapterId;
  device?: KeyboardDevice | null;
}

export interface WriteDeviceOptions {
  ack?: boolean;
  inherit?: boolean;
}

export interface ActionBindingRequest {
  scope?: BindingScope;
  layer?: number;
  action: KeySilkActionId | string;
  binding: BindingId | StructuredBinding;
}

export type StructuredBinding =
  | { type: "mouse"; action: string }
  | { type: "text"; value: string }
  | { type: "macro"; steps: unknown[] }
  | { type: "open_program"; path: string };

export interface ActionBindingResult {
  action: string;
  binding: BindingId | null;
  raw: ParsedRecordBinding | null;
  offset: number | null;
}

export interface BindingModel {
  sdkVersion?: string;
  adapter?: AdapterId;
  layout?: string;
  base?: Partial<Record<KeySilkActionId | string, BindingId | StructuredBinding | null>>;
  extended?: Partial<Record<KeySilkActionId | string, BindingId | StructuredBinding | null>>;
  hostActions?: Array<HostOpenUrlProfileAction | HostOpenPathProfileAction | HotkeyOpenUrlProfileAction | HotkeyOpenPathProfileAction | HotkeyTextProfileAction>;
  simpleMacroActions?: SimpleMacroTapsRequest[];
}

export interface HostOpenUrlRequest {
  scope?: BindingScope;
  action: KeySilkActionId | string;
  url: string;
}

export interface HostOpenPathRequest {
  scope?: BindingScope;
  action: KeySilkActionId | string;
  path: string;
}

export interface HotkeyOpenUrlRequest {
  scope?: BindingScope;
  action: KeySilkActionId | string;
  url: string;
  binding?: HotkeyCompanionBinding;
}

export interface HotkeyOpenPathRequest {
  scope?: BindingScope;
  action: KeySilkActionId | string;
  path: string;
  binding?: HotkeyCompanionBinding;
}

export interface HotkeyTextRequest {
  scope?: BindingScope;
  action: KeySilkActionId | string;
  text: string;
  binding?: HotkeyCompanionBinding;
}

export interface HostOpenUrlProfileAction {
  type: "open_url";
  adapter: AdapterId;
  layout: string;
  scope: BindingScope;
  action: KeySilkActionId | string;
  url: string;
  reportPrefixHex: string;
  note?: string;
}

export interface HostOpenPathProfileAction {
  type: "open_path";
  adapter: AdapterId;
  layout: string;
  scope: BindingScope;
  action: KeySilkActionId | string;
  path: string;
  reportPrefixHex: string;
  note?: string;
}

export interface HotkeyOpenUrlProfileAction {
  type: "hotkey_open_url";
  adapter: AdapterId;
  layout: string;
  scope: BindingScope;
  action: KeySilkActionId | string;
  url: string;
  binding: HotkeyCompanionBinding;
  hotkey: string;
  note?: string;
}

export interface HotkeyOpenPathProfileAction {
  type: "hotkey_open_path";
  adapter: AdapterId;
  layout: string;
  scope: BindingScope;
  action: KeySilkActionId | string;
  path: string;
  binding: HotkeyCompanionBinding;
  hotkey: string;
  note?: string;
}

export interface HotkeyTextProfileAction {
  type: "hotkey_text";
  adapter: AdapterId;
  layout: string;
  scope: BindingScope;
  action: KeySilkActionId | string;
  text: string;
  binding: HotkeyCompanionBinding;
  hotkey: string;
  note?: string;
}

export interface HostActionProfile {
  version: 1;
  adapter: AdapterId;
  layout: string;
  actions: Array<HostOpenUrlProfileAction | HostOpenPathProfileAction | HotkeyOpenUrlProfileAction | HotkeyOpenPathProfileAction | HotkeyTextProfileAction>;
}

export type CompanionProfileAction =
  | HostOpenUrlProfileAction
  | HostOpenPathProfileAction
  | HotkeyOpenUrlProfileAction
  | HotkeyOpenPathProfileAction
  | HotkeyTextProfileAction;

export interface CompanionRuntimeProfile extends Omit<HostActionProfile, "adapter" | "layout" | "actions"> {
  adapter: AdapterId | string | null;
  layout: string | null;
  actions: CompanionProfileAction[];
}

export interface CompanionValidationResult {
  ok: boolean;
  errors: string[];
  warnings: string[];
  profile: CompanionRuntimeProfile;
}

export interface CompanionTriggerPlan {
  hotkeys: Array<{
    binding: string;
    hotkey: string;
    actions: CompanionProfileAction[];
  }>;
  rawReports: Array<{
    reportPrefixHex: string;
    actions: CompanionProfileAction[];
  }>;
}

export interface CompanionHostHandlers {
  openUrl?: (url: string, action: CompanionProfileAction) => unknown;
  openPath?: (path: string, action: CompanionProfileAction) => unknown;
  pasteText?: (text: string, action: CompanionProfileAction) => unknown;
}

export interface SimpleMacroTap {
  key: BindingId | string;
  delayMs?: number;
}

export interface SimpleMacroTapsRequest {
  scope?: "extended";
  action: KeySilkActionId | string;
  label?: string;
  taps: SimpleMacroTap[];
}

export function listAdapters(): AdapterInfo[];
export function listDevices(): KeyboardDevice[];
export function readDevice(device?: KeyboardDevice): KeyboardConfig;
export function writeDevice(config: KeyboardConfig, maybeConfig?: null, options?: WriteDeviceOptions): void;
export function writeDevice(device: KeyboardDevice, config: KeyboardConfig, options?: WriteDeviceOptions): void;
export function importConfig(rawConfig: Buffer | Uint8Array, options?: ImportConfigOptions): KeyboardConfig;
export function exportConfig(config: KeyboardConfig | Buffer): Buffer;
export function getLayout(deviceOrConfig?: KeyboardDevice | KeyboardConfig): KeyboardLayout;
export function getBindings(deviceOrConfig?: KeyboardDevice | KeyboardConfig): Record<BindingId, BindingInfo>;
export function getCapabilities(deviceOrConfig?: KeyboardDevice | KeyboardConfig): CapabilityInfo;
export function getActionBinding(
  config: KeyboardConfig,
  actionId: KeySilkActionId | string,
  options?: { scope?: BindingScope; layer?: number }
): ActionBindingResult | null;
export function setActionBinding(config: KeyboardConfig, request: ActionBindingRequest): KeyboardConfig;
export function setActionBinding(
  config: KeyboardConfig,
  actionId: KeySilkActionId | string,
  bindingId: BindingId | StructuredBinding,
  options?: { scope?: BindingScope; layer?: number }
): KeyboardConfig;
export function applyBindingModel(config: KeyboardConfig, model: BindingModel): KeyboardConfig;
export function setHostOpenUrlAction(config: KeyboardConfig, request: HostOpenUrlRequest): KeyboardConfig;
export function setHostOpenPathAction(config: KeyboardConfig, request: HostOpenPathRequest): KeyboardConfig;
export function setHotkeyOpenUrlAction(config: KeyboardConfig, request: HotkeyOpenUrlRequest): KeyboardConfig;
export function setHotkeyOpenPathAction(config: KeyboardConfig, request: HotkeyOpenPathRequest): KeyboardConfig;
export function setHotkeyTextAction(config: KeyboardConfig, request: HotkeyTextRequest): KeyboardConfig;
export function setSimpleMacroTapsAction(config: KeyboardConfig, request: SimpleMacroTapsRequest): KeyboardConfig;
export function exportHostActionProfile(config: KeyboardConfig): HostActionProfile;
export function normalizeCompanionProfile(profile: Partial<HostActionProfile>): CompanionRuntimeProfile;
export function validateCompanionProfile(profile: Partial<HostActionProfile>): CompanionValidationResult;
export function getCompanionTriggers(profile: Partial<HostActionProfile>): CompanionTriggerPlan;
export function dispatchCompanionAction(action: CompanionProfileAction, host: CompanionHostHandlers): unknown;
export function handleCompanionHotkey(profile: Partial<HostActionProfile>, bindingOrHotkey: string, host: CompanionHostHandlers): unknown[];
export function handleCompanionRawReport(profile: Partial<HostActionProfile>, reportHex: string, host: CompanionHostHandlers): unknown[];
