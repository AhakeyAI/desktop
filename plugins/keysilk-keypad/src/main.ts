import { createRequire } from "node:module";
import { definePlugin, servePlugin, type AhaKeyHost } from "@ahakey/plugin-sdk";

const require = createRequire(import.meta.url);
const keypadSdk = require("@ahakey/portable-keypad-sdk") as PortableKeypadSdk;

type JsonRecord = Record<string, unknown>;

interface PortableKeypadSdk {
  listAdapters(): unknown[];
  getLayout(deviceOrConfig?: unknown): unknown;
  getBindings(deviceOrConfig?: unknown): unknown;
  getCapabilities(deviceOrConfig?: unknown): unknown;
  validateCompanionProfile(profile: unknown): CompanionValidationResult;
  getCompanionTriggers(profile: unknown): CompanionTriggerPlan;
  handleCompanionHotkey(profile: unknown, bindingOrHotkey: string, host: CompanionHostHandlers): unknown[];
}

let host: AhaKeyHost | undefined;
let activeProfile: unknown;
const registeredHotkeys = new Map<string, string>();

interface CompanionValidationResult {
  ok: boolean;
  errors: string[];
  warnings: string[];
  profile: unknown;
}

interface CompanionTriggerPlan {
  hotkeys: Array<{
    binding: string;
    hotkey: string;
    actions: unknown[];
  }>;
  rawReports: Array<{
    reportPrefixHex: string;
    actions: unknown[];
  }>;
}

interface CompanionHostHandlers {
  openUrl(url: string): Promise<unknown>;
  openPath(path: string): Promise<unknown>;
  pasteText(text: string): Promise<unknown>;
}

function asRecord(value: unknown, method: string): JsonRecord {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return value as JsonRecord;
  }
  throw new Error(`${method} expects an object parameter`);
}

async function unregisterAllHotkeys(): Promise<void> {
  if (host === undefined) return;
  for (const token of registeredHotkeys.values()) {
    try {
      await host.unregisterGlobalHotkey(token);
    } catch {
      // Best effort cleanup; stale tokens die with the host process.
    }
  }
  registeredHotkeys.clear();
}

async function installCompanionProfile(profile: unknown): Promise<{
  installedHotkeys: Array<{ hotkey: string; token: string }>;
  rawReports: CompanionTriggerPlan["rawReports"];
  warnings: string[];
}> {
  if (host === undefined) {
    throw new Error("AhaKey host is not initialized");
  }
  const validation = keypadSdk.validateCompanionProfile(profile);
  if (!validation.ok) {
    throw new Error(`Invalid companion profile: ${validation.errors.join("; ")}`);
  }

  await unregisterAllHotkeys();
  activeProfile = validation.profile;

  const triggers = keypadSdk.getCompanionTriggers(activeProfile);
  const installedHotkeys: Array<{ hotkey: string; token: string }> = [];
  for (const trigger of triggers.hotkeys) {
    const result = await host.registerGlobalHotkey(trigger.hotkey, "keysilk/hotkeyTriggered");
    registeredHotkeys.set(trigger.hotkey, result.token);
    installedHotkeys.push({ hotkey: trigger.hotkey, token: result.token });
  }

  return {
    installedHotkeys,
    rawReports: triggers.rawReports,
    warnings: validation.warnings,
  };
}

async function dispatchHotkey(params: unknown): Promise<{ dispatched: number }> {
  if (activeProfile === undefined) {
    return { dispatched: 0 };
  }
  if (host === undefined) {
    throw new Error("AhaKey host is not initialized");
  }
  const record = asRecord(params, "keysilk/hotkeyTriggered");
  const hotkey = typeof record.hotkey === "string" ? record.hotkey : "";
  const results = keypadSdk.handleCompanionHotkey(activeProfile, hotkey, {
    openUrl: (url) => host!.openUrl(url),
    openPath: (path) => host!.openPath(path),
    pasteText: (text) => host!.pasteText(text),
  });
  await Promise.all(results);
  return { dispatched: results.length };
}

servePlugin(definePlugin({
  name: "KeySilk Portable Keypad",
  version: "0.1.0",
  methods: {
    "keysilk/listAdapters": () => keypadSdk.listAdapters(),
    "keysilk/getLayout": () => keypadSdk.getLayout({ adapter: "keysilk_v1" }),
    "keysilk/getBindings": () => keypadSdk.getBindings({ adapter: "keysilk_v1" }),
    "keysilk/getCapabilities": () => keypadSdk.getCapabilities({ adapter: "keysilk_v1" }),
    "keysilk/validateCompanionProfile": (params) => {
      const record = asRecord(params, "keysilk/validateCompanionProfile");
      return keypadSdk.validateCompanionProfile(record.profile);
    },
    "keysilk/getCompanionTriggers": (params) => {
      const record = asRecord(params, "keysilk/getCompanionTriggers");
      return keypadSdk.getCompanionTriggers(record.profile);
    },
    "keysilk/installCompanionProfile": async (params) => {
      const record = asRecord(params, "keysilk/installCompanionProfile");
      return installCompanionProfile(record.profile);
    },
    "keysilk/uninstallCompanionProfile": async () => {
      await unregisterAllHotkeys();
      activeProfile = undefined;
      return { uninstalled: true };
    },
    "keysilk/hotkeyTriggered": dispatchHotkey,
  },
  onInitialize(_params, connectedHost) {
    host = connectedHost;
  },
  async onInitialized() {
    await host?.log("keysilk-keypad plugin online");
    const required = [
      "host/openUrl",
      "host/openPath",
      "host/pasteText",
      "host/registerGlobalHotkey",
      "host/unregisterGlobalHotkey",
    ];
    const missing = required.filter((method) => !host?.supports(method));
    if (missing.length > 0) {
      await host?.log(`keysilk-keypad: companion runtime is limited; missing ${missing.join(", ")}`, "warn");
    }
  },
  async onShutdown() {
    await unregisterAllHotkeys();
    await host?.log("keysilk-keypad plugin shutdown");
  },
}));
