const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const {
  actionOrder3Key1Knob,
  getBindingForAction,
  keySilkBindings,
  patchSimpleMacroTaps,
  parseConfig,
  patchShortcutBinding,
  summarizeConfig,
} = require("./config-codec");

const layout3Key1Knob = require("./layout-3key-1knob.json");
const projectRoot = path.resolve(__dirname, "..", "..", "..");
const hidTool = path.join(projectRoot, "tools", "bin", "KeySilkHidTool.exe");

const adapterInfo = {
  id: "keysilk_v1",
  brand: "KeySilk / COIDEA",
  vid: 0x4132,
  pid: 0x2107,
  layout: "keysilk_3key_1knob",
  actions: actionOrder3Key1Knob,
  bindings: Object.keys(keySilkBindings),
};

const capabilityInfo = {
  adapter: adapterInfo.id,
  layout: adapterInfo.layout,
  states: {
    done: "Implemented and hardware verified.",
    observed: "Parsed from captured configs, but not fully exercised as a new SDK write target.",
    inferred: "Generated from a consistent byte pattern and pending batch hardware verification.",
    blocked: "Needs factory samples or more reverse engineering before writes are enabled.",
  },
  features: [
    { id: "device.detect", label: "Detect KeySilk config interface", state: "done" },
    { id: "device.read", label: "Read raw config", state: "done" },
    { id: "device.write", label: "Write raw config", state: "done" },
    { id: "actions.base", label: "Patch base action records", state: "done" },
    { id: "actions.extended", label: "Create and patch extended action records", state: "done" },
    { id: "bindings.keyboard.verified", label: "Verified keyboard keys", state: "done", bindings: ["A", "B", "C", "Z", "Digit0", "Digit1", "Esc", "Enter", "Space"] },
    { id: "bindings.keyboard.observed", label: "Observed digit keys", state: "observed", bindings: ["Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8"] },
    { id: "bindings.keyboard.inferred", label: "Inferred keyboard keys", state: "inferred", bindings: ["D-Y", "Digit9"] },
    { id: "bindings.shortcuts.verified", label: "Verified modifier shortcuts", state: "done", bindings: ["Ctrl", "Shift", "Alt", "Win", "CtrlC", "CtrlV", "CtrlZ"] },
    { id: "bindings.shortcuts.inferred", label: "Inferred shortcut combinations", state: "inferred", bindings: ["CtrlA", "CtrlX", "CtrlY", "CtrlS", "CtrlP", "CtrlF", "CtrlAltShiftB", "CtrlAltShiftC", "CtrlAltShiftD", "CtrlAltShiftE", "CtrlAltShiftF", "CtrlAltShiftG", "CtrlAltShiftH", "CtrlAltShiftI"] },
    { id: "bindings.media", label: "Media controls", state: "done", bindings: ["Mute", "VolumeDown", "VolumeUp", "PlayPause"] },
    { id: "bindings.layer", label: "Scene switching controls", state: "done", bindings: ["NextLayer", "PreviousLayer"] },
    { id: "bindings.host_open_url", label: "Host-assisted open URL", state: "done", bindings: ["HostOpenUrl"] },
    { id: "bindings.host_open_path", label: "Host-assisted open file/program path", state: "done", bindings: ["HostOpenPath"] },
    { id: "bindings.mouse", label: "Mouse buttons", state: "done", bindings: ["MouseLeftClick", "MouseRightClick", "MouseMiddleClick"] },
    { id: "bindings.mouse_wheel", label: "Mouse wheel", state: "done", bindings: ["MouseWheelUp", "MouseWheelDown"] },
    { id: "bindings.modified_mouse_wheel", label: "Modified mouse wheel", state: "done", bindings: ["CtrlMouseWheelUp", "CtrlMouseWheelDown"] },
    { id: "bindings.macro", label: "Simple macro taps", state: "done", bindings: ["MacroObserved"] },
    { id: "bindings.text", label: "Text records", state: "observed", bindings: ["TextObserved"] },
    { id: "bindings.open_program", label: "Host-assisted built-in open actions", state: "observed", bindings: ["OpenCalculatorObserved"] },
    { id: "bindings.text_write", label: "Text slot writes", state: "blocked" },
    { id: "bindings.macro_complex", label: "Complex macro sequences", state: "blocked" },
    { id: "bindings.open_program_write", label: "Standalone open program/path writes", state: "blocked" },
    { id: "device.restore_defaults", label: "Factory restore/defaults", state: "blocked" },
    { id: "device.firmware", label: "Firmware update operations", state: "blocked" },
  ],
};

const hotkeyCompanionBindings = [
  "CtrlAltShiftB",
  "CtrlAltShiftC",
  "CtrlAltShiftD",
  "CtrlAltShiftE",
  "CtrlAltShiftF",
  "CtrlAltShiftG",
  "CtrlAltShiftH",
  "CtrlAltShiftI",
];

function hotkeyToAccelerator(binding) {
  const suffix = String(binding || "").replace(/^CtrlAltShift/, "");
  return `Ctrl+Alt+Shift+${suffix}`;
}

function runHid(args, options = {}) {
  if (!fs.existsSync(hidTool)) {
    throw new Error(
      `KeySilk HID transport helper not found at ${hidTool}. `
      + "Inside AhaKey desktop, call the SDK's pure config/profile APIs from a plugin "
      + "and route device IO through host-provided HID methods instead.",
    );
  }
  const result = spawnSync(hidTool, args, {
    encoding: "utf8",
    stdio: options.inherit ? "inherit" : "pipe",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(output || `KeySilk HID tool failed with exit code ${result.status}`);
  }
  return {
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

function parseDeviceList(output) {
  const devices = [];
  let current = null;
  for (const line of output.split(/\r?\n/)) {
    const pathMatch = line.match(/^\[(\d+)\]\s+(.+)$/);
    if (pathMatch) {
      current = {
        adapter: adapterInfo.id,
        brand: adapterInfo.brand,
        vid: adapterInfo.vid,
        pid: adapterInfo.pid,
        path: pathMatch[2],
        interfaceIndex: Number(pathMatch[1]),
      };
      devices.push(current);
      continue;
    }

    const capsMatch = line.match(/UsagePage=0x([0-9a-fA-F]+)\s+Usage=0x([0-9a-fA-F]+)\s+Input=(\d+)\s+Output=(\d+)\s+Feature=(\d+)/);
    if (current && capsMatch) {
      current.usagePage = Number.parseInt(capsMatch[1], 16);
      current.usage = Number.parseInt(capsMatch[2], 16);
      current.inputReportLength = Number(capsMatch[3]);
      current.outputReportLength = Number(capsMatch[4]);
      current.featureReportLength = Number(capsMatch[5]);
      current.isConfigInterface = current.usagePage === 0xff00 && current.usage === 0x0001;
    }
  }
  return devices;
}

function readConfigFile(filePath) {
  return fs.readFileSync(filePath);
}

function writeConfigFile(filePath, rawConfig) {
  fs.writeFileSync(filePath, rawConfig);
}

function inspectConfig(rawConfig) {
  return parseConfig(rawConfig);
}

function importConfig(rawConfig, options = {}) {
  const raw = Buffer.from(rawConfig);
  return {
    adapter: adapterInfo.id,
    device: options.device || null,
    raw,
    parsed: inspectConfig(raw),
  };
}

function exportConfig(config) {
  return Buffer.from(Buffer.isBuffer(config) ? config : config.raw);
}

function inspectConfigFile(filePath) {
  return inspectConfig(readConfigFile(filePath));
}

function summarizeConfigFile(filePath) {
  return summarizeConfig(readConfigFile(filePath));
}

function getLayout() {
  return JSON.parse(JSON.stringify(layout3Key1Knob));
}

function getBindings() {
  return Object.fromEntries(
    Object.entries(keySilkBindings).map(([id, binding]) => [
      id,
      {
        id,
        label: binding.label,
        category: binding.category,
        verification: binding.verification,
        aliases: binding.aliases || [],
      },
    ]),
  );
}

function getCapabilities() {
  return JSON.parse(JSON.stringify(capabilityInfo));
}

function getActionBinding(configOrRaw, actionId, options = {}) {
  const scope = options.scope || (actionId.startsWith("extended.") ? "extended" : "base");
  const raw = Buffer.isBuffer(configOrRaw) ? configOrRaw : configOrRaw.raw;
  const normalizedAction = actionId.startsWith("extended.") || scope === "base"
    ? actionId
    : `extended.${actionId}`;
  return getBindingForAction(raw, normalizedAction);
}

function setBinding(rawConfig, actionId, bindingId) {
  return patchShortcutBinding(rawConfig, actionId, bindingId);
}

function setActionBinding(configOrRaw, actionId, bindingId, options = {}) {
  const scope = options.scope || (actionId.startsWith("extended.") ? "extended" : "base");
  const normalizedAction = actionId.startsWith("extended.") || scope === "base"
    ? actionId
    : `extended.${actionId}`;
  const raw = Buffer.isBuffer(configOrRaw) ? configOrRaw : configOrRaw.raw;
  const patched = setBinding(raw, normalizedAction, bindingId);
  if (Buffer.isBuffer(configOrRaw)) return patched;

  configOrRaw.raw = patched;
  configOrRaw.parsed = inspectConfig(patched);
  return configOrRaw;
}

function assertUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch (error) {
    throw new Error(`Invalid URL for host-assisted open action: ${url}`);
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`Only http/https URLs are supported for host-assisted open action: ${url}`);
  }
  return parsed.toString();
}

function setHostOpenUrlAction(config, request) {
  if (!config || Buffer.isBuffer(config)) {
    throw new Error("setHostOpenUrlAction requires an imported config object");
  }
  const action = request.action;
  const scope = request.scope || "extended";
  const url = assertUrl(request.url);

  setActionBinding(config, action, "HostOpenUrl", { scope });
  config.hostActions = (config.hostActions || []).filter((item) => !(item.type === "open_url" && item.action === action && item.scope === scope));
  config.hostActions.push({
    type: "open_url",
    adapter: adapterInfo.id,
    layout: adapterInfo.layout,
    scope,
    action,
    url,
    reportPrefixHex: "00150403",
    note: "Host-assisted KeySilk open URL trigger. The URL is executed by a companion app, not stored in the keypad config.",
  });
  return config;
}

function assertHostPath(targetPath) {
  if (typeof targetPath !== "string" || !targetPath.trim()) {
    throw new Error("Host-assisted open path requires a non-empty path");
  }
  return targetPath.trim();
}

function setHostOpenPathAction(config, request) {
  if (!config || Buffer.isBuffer(config)) {
    throw new Error("setHostOpenPathAction requires an imported config object");
  }
  const action = request.action;
  const scope = request.scope || "extended";
  const targetPath = assertHostPath(request.path);

  setActionBinding(config, action, "HostOpenPath", { scope });
  config.hostActions = (config.hostActions || []).filter((item) => !(item.type === "open_path" && item.action === action && item.scope === scope));
  config.hostActions.push({
    type: "open_path",
    adapter: adapterInfo.id,
    layout: adapterInfo.layout,
    scope,
    action,
    path: targetPath,
    reportPrefixHex: "00150404",
    note: "Host-assisted KeySilk open file/program trigger. The path is executed by a companion app, not stored in the keypad config.",
  });
  return config;
}

function defaultHotkeyBindingForAction(action) {
  const index = actionOrder3Key1Knob.indexOf(action);
  return hotkeyCompanionBindings[index >= 0 ? index : 0];
}

function normalizeHotkeyBinding(binding, action) {
  const hotkeyBinding = binding || defaultHotkeyBindingForAction(action);
  if (!hotkeyCompanionBindings.includes(hotkeyBinding)) {
    throw new Error(`Unsupported hotkey companion binding "${hotkeyBinding}". Supported: ${hotkeyCompanionBindings.join(", ")}`);
  }
  return hotkeyBinding;
}

function setHotkeyOpenUrlAction(config, request) {
  if (!config || Buffer.isBuffer(config)) {
    throw new Error("setHotkeyOpenUrlAction requires an imported config object");
  }
  const action = request.action;
  const scope = request.scope || "extended";
  const url = assertUrl(request.url);
  const binding = normalizeHotkeyBinding(request.binding, action);

  setActionBinding(config, action, binding, { scope });
  config.hostActions = (config.hostActions || []).filter((item) => !(item.type === "hotkey_open_url" && item.action === action && item.scope === scope));
  config.hostActions.push({
    type: "hotkey_open_url",
    adapter: adapterInfo.id,
    layout: adapterInfo.layout,
    scope,
    action,
    url,
    binding,
    hotkey: hotkeyToAccelerator(binding),
    note: "Bluetooth-compatible host open URL action. The keypad emits a reserved hotkey; the target URL is executed by a companion app.",
  });
  return config;
}

function setHotkeyOpenPathAction(config, request) {
  if (!config || Buffer.isBuffer(config)) {
    throw new Error("setHotkeyOpenPathAction requires an imported config object");
  }
  const action = request.action;
  const scope = request.scope || "extended";
  const targetPath = assertHostPath(request.path);
  const binding = normalizeHotkeyBinding(request.binding, action);

  setActionBinding(config, action, binding, { scope });
  config.hostActions = (config.hostActions || []).filter((item) => !(item.type === "hotkey_open_path" && item.action === action && item.scope === scope));
  config.hostActions.push({
    type: "hotkey_open_path",
    adapter: adapterInfo.id,
    layout: adapterInfo.layout,
    scope,
    action,
    path: targetPath,
    binding,
    hotkey: hotkeyToAccelerator(binding),
    note: "Bluetooth-compatible host open file/program action. The keypad emits a reserved hotkey; the target path is executed by a companion app.",
  });
  return config;
}

function assertHotkeyText(text) {
  if (typeof text !== "string" || text.length === 0) {
    throw new Error("Hotkey text action requires non-empty text");
  }
  if (text.length > 4096) {
    throw new Error("Hotkey text action text is too long; max 4096 characters");
  }
  return text;
}

function setHotkeyTextAction(config, request) {
  if (!config || Buffer.isBuffer(config)) {
    throw new Error("setHotkeyTextAction requires an imported config object");
  }
  const action = request.action;
  const scope = request.scope || "extended";
  const text = assertHotkeyText(request.text);
  const binding = normalizeHotkeyBinding(request.binding, action);

  setActionBinding(config, action, binding, { scope });
  config.hostActions = (config.hostActions || []).filter((item) => !(item.type === "hotkey_text" && item.action === action && item.scope === scope));
  config.hostActions.push({
    type: "hotkey_text",
    adapter: adapterInfo.id,
    layout: adapterInfo.layout,
    scope,
    action,
    text,
    binding,
    hotkey: hotkeyToAccelerator(binding),
    note: "Host-side text action. The keypad emits a reserved hotkey; the companion pastes this text at the current cursor.",
  });
  return config;
}

function setSimpleMacroTapsAction(config, request) {
  if (!config || Buffer.isBuffer(config)) {
    throw new Error("setSimpleMacroTapsAction requires an imported config object");
  }
  const action = request.action;
  const scope = request.scope || "extended";
  if (scope !== "extended") {
    throw new Error("Simple macro taps require extended scope for current KeySilk firmware");
  }
  const actionId = action.startsWith("extended.") ? action : `extended.${action}`;
  const patched = patchSimpleMacroTaps(config.raw, actionId, request.taps, request.label || "Macro");
  config.raw = patched;
  config.parsed = inspectConfig(patched);
  return config;
}

function exportHostActionProfile(config) {
  return {
    version: 1,
    adapter: adapterInfo.id,
    layout: adapterInfo.layout,
    actions: config.hostActions || [],
  };
}

function toHex(bytes) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join(" ");
}

function extractExtendedSamples(rawConfig) {
  const parsed = inspectConfig(rawConfig);
  return parsed.extendedRecords
    .filter((record) => record.binding)
    .map((record) => ({
      adapter: adapterInfo.id,
      layout: adapterInfo.layout,
      action: `extended.${record.action}`,
      offset: record.offset,
      length: record.length,
      binding: record.binding,
      recordHex: toHex(rawConfig.subarray(record.offset, record.offset + record.length)),
      declaredLength: parsed.declaredLength,
      rawLength: parsed.rawLength,
    }));
}

function saveExtendedSampleFile(inputPath, sampleName, outputDir) {
  const rawConfig = readConfigFile(inputPath);
  const samples = extractExtendedSamples(rawConfig);
  const safeName = sampleName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const targetDir = outputDir || path.join(__dirname, "extended-samples");
  const targetPath = path.join(targetDir, `${safeName}.json`);
  fs.mkdirSync(targetDir, { recursive: true });
  fs.writeFileSync(targetPath, `${JSON.stringify({ source: inputPath, samples }, null, 2)}\n`);
  return { targetPath, samples };
}

function patchConfigFile(inputPath, actionId, bindingId, outputPath) {
  const patched = setBinding(readConfigFile(inputPath), actionId, bindingId);
  writeConfigFile(outputPath, patched);
  return patched;
}

function listDevices() {
  return parseDeviceList(runHid(["list"]).stdout).filter((device) => device.isConfigInterface);
}

function readDevice(device = null) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "keysilk-sdk-"));
  const outputPath = path.join(tempDir, "config.bin");
  try {
    runHid(["read", outputPath]);
    return importConfig(readConfigFile(outputPath), { device });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function writeDevice(deviceOrConfig, maybeConfig, options = {}) {
  const config = maybeConfig || deviceOrConfig;
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "keysilk-sdk-"));
  const inputPath = path.join(tempDir, "config.bin");
  try {
    writeConfigFile(inputPath, exportConfig(config));
    runHid([options.ack ? "write" : "write-noack", inputPath], { inherit: Boolean(options.inherit) });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

module.exports = {
  adapterInfo,
  extractExtendedSamples,
  exportConfig,
  getActionBinding,
  getBindings,
  getCapabilities,
  getLayout,
  importConfig,
  inspectConfig,
  inspectConfigFile,
  listDevices,
  patchConfigFile,
  readConfigFile,
  readDevice,
  saveExtendedSampleFile,
  setActionBinding,
  setBinding,
  setHostOpenPathAction,
  setHostOpenUrlAction,
  setHotkeyOpenPathAction,
  setHotkeyOpenUrlAction,
  setHotkeyTextAction,
  setSimpleMacroTapsAction,
  exportHostActionProfile,
  summarizeConfig,
  summarizeConfigFile,
  writeDevice,
  writeConfigFile,
};
