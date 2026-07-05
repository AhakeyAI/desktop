const HOTKEY_ACCELERATORS = {
  CtrlAltShiftB: "Ctrl+Alt+Shift+B",
  CtrlAltShiftC: "Ctrl+Alt+Shift+C",
  CtrlAltShiftD: "Ctrl+Alt+Shift+D",
  CtrlAltShiftE: "Ctrl+Alt+Shift+E",
  CtrlAltShiftF: "Ctrl+Alt+Shift+F",
  CtrlAltShiftG: "Ctrl+Alt+Shift+G",
  CtrlAltShiftH: "Ctrl+Alt+Shift+H",
  CtrlAltShiftI: "Ctrl+Alt+Shift+I",
};

const HOTKEY_ACTION_TYPES = new Set([
  "hotkey_open_url",
  "hotkey_open_path",
  "hotkey_text",
]);

const RAW_REPORT_ACTION_TYPES = new Set([
  "open_url",
  "open_path",
]);

function normalizeHex(value) {
  return String(value || "").replace(/[^0-9a-f]/gi, "").toLowerCase();
}

function normalizeHotkey(value) {
  return String(value || "").replace(/\s+/g, "").toLowerCase();
}

function normalizeCompanionProfile(profile = {}) {
  const actions = (profile.actions || []).map((action) => {
    const next = { ...action };
    if (HOTKEY_ACTION_TYPES.has(next.type)) {
      next.binding = next.binding || "CtrlAltShiftB";
      next.hotkey = next.hotkey || HOTKEY_ACCELERATORS[next.binding] || next.binding;
    }
    return next;
  });

  return {
    version: profile.version || 1,
    adapter: profile.adapter || actions[0]?.adapter || null,
    layout: profile.layout || actions[0]?.layout || null,
    actions,
  };
}

function validateCompanionProfile(profile = {}) {
  const normalized = normalizeCompanionProfile(profile);
  const errors = [];
  const warnings = [];
  const hotkeyCounts = new Map();
  const reportCounts = new Map();

  normalized.actions.forEach((action, index) => {
    if (!action || typeof action !== "object") {
      errors.push(`actions[${index}] must be an object`);
      return;
    }

    if (HOTKEY_ACTION_TYPES.has(action.type)) {
      const key = action.binding || action.hotkey;
      if (!key) {
        errors.push(`actions[${index}] hotkey action is missing binding/hotkey`);
      } else {
        hotkeyCounts.set(key, (hotkeyCounts.get(key) || 0) + 1);
      }
    } else if (RAW_REPORT_ACTION_TYPES.has(action.type)) {
      const prefix = normalizeHex(action.reportPrefixHex);
      if (!prefix) {
        errors.push(`actions[${index}] raw-report action is missing reportPrefixHex`);
      } else {
        reportCounts.set(prefix, (reportCounts.get(prefix) || 0) + 1);
      }
    } else {
      errors.push(`actions[${index}] unsupported companion action type "${action.type || "unknown"}"`);
    }

    if (action.type === "open_url" || action.type === "hotkey_open_url") {
      if (!action.url) errors.push(`actions[${index}] URL action is missing url`);
    }
    if (action.type === "open_path" || action.type === "hotkey_open_path") {
      if (!action.path) errors.push(`actions[${index}] path action is missing path`);
    }
    if (action.type === "hotkey_text") {
      if (!action.text) errors.push(`actions[${index}] text action is missing text`);
    }
  });

  for (const [key, count] of hotkeyCounts) {
    if (count > 1) {
      warnings.push(`Multiple companion actions share hotkey "${key}". The host app cannot distinguish physical keypad actions unless each one uses a unique reserved hotkey.`);
    }
  }

  for (const [prefix, count] of reportCounts) {
    if (count > 1) {
      warnings.push(`Multiple companion actions share raw report prefix "${prefix}". The host app will dispatch all matching actions.`);
    }
  }

  return { ok: errors.length === 0, errors, warnings, profile: normalized };
}

function getCompanionTriggers(profile = {}) {
  const normalized = normalizeCompanionProfile(profile);
  const hotkeys = [];
  const rawReports = [];

  normalized.actions.forEach((action) => {
    if (HOTKEY_ACTION_TYPES.has(action.type)) {
      const existing = hotkeys.find((item) => item.binding === action.binding && item.hotkey === action.hotkey);
      if (existing) {
        existing.actions.push(action);
      } else {
        hotkeys.push({
          binding: action.binding,
          hotkey: action.hotkey,
          actions: [action],
        });
      }
    }

    if (RAW_REPORT_ACTION_TYPES.has(action.type)) {
      const prefixHex = normalizeHex(action.reportPrefixHex);
      const existing = rawReports.find((item) => item.reportPrefixHex === prefixHex);
      if (existing) {
        existing.actions.push(action);
      } else {
        rawReports.push({
          reportPrefixHex: prefixHex,
          actions: [action],
        });
      }
    }
  });

  return { hotkeys, rawReports };
}

function dispatchCompanionAction(action, host) {
  if (!host || typeof host !== "object") {
    throw new Error("Companion host handlers are required");
  }

  if (action.type === "open_url" || action.type === "hotkey_open_url") {
    if (typeof host.openUrl !== "function") {
      throw new Error("Companion host handler openUrl(url, action) is required");
    }
    return host.openUrl(action.url, action);
  }

  if (action.type === "open_path" || action.type === "hotkey_open_path") {
    if (typeof host.openPath !== "function") {
      throw new Error("Companion host handler openPath(path, action) is required");
    }
    return host.openPath(action.path, action);
  }

  if (action.type === "hotkey_text") {
    if (typeof host.pasteText !== "function") {
      throw new Error("Companion host handler pasteText(text, action) is required");
    }
    return host.pasteText(action.text, action);
  }

  throw new Error(`Unsupported companion action type "${action.type || "unknown"}"`);
}

function handleCompanionHotkey(profile, bindingOrHotkey, host) {
  const target = normalizeHotkey(bindingOrHotkey);
  const actions = normalizeCompanionProfile(profile).actions.filter((action) =>
    HOTKEY_ACTION_TYPES.has(action.type)
      && (normalizeHotkey(action.binding) === target || normalizeHotkey(action.hotkey) === target),
  );
  return actions.map((action) => dispatchCompanionAction(action, host));
}

function handleCompanionRawReport(profile, reportHex, host) {
  const report = normalizeHex(reportHex);
  const actions = normalizeCompanionProfile(profile).actions.filter((action) =>
    RAW_REPORT_ACTION_TYPES.has(action.type)
      && report.startsWith(normalizeHex(action.reportPrefixHex)),
  );
  return actions.map((action) => dispatchCompanionAction(action, host));
}

module.exports = {
  dispatchCompanionAction,
  getCompanionTriggers,
  handleCompanionHotkey,
  handleCompanionRawReport,
  normalizeCompanionProfile,
  validateCompanionProfile,
};
