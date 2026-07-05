const keySilkV1 = require("./adapters/keysilk-v1/adapter");
const companionRuntime = require("./companion-runtime");

const adapters = {
  [keySilkV1.adapterInfo.id]: keySilkV1,
};

function getAdapter(adapterId) {
  const adapter = adapters[adapterId];
  if (!adapter) {
    throw new Error(`Unsupported keyboard adapter: ${adapterId}`);
  }
  return adapter;
}

function listAdapters() {
  return Object.values(adapters).map((adapter) => adapter.adapterInfo);
}

function listDevices() {
  return Object.values(adapters).flatMap((adapter) => adapter.listDevices());
}

function resolveAdapterForDevice(device) {
  if (device && device.adapter) return getAdapter(device.adapter);
  return keySilkV1;
}

function readDevice(device) {
  return resolveAdapterForDevice(device).readDevice(device);
}

function writeDevice(deviceOrConfig, maybeConfig, options) {
  const config = maybeConfig || deviceOrConfig;
  const adapter = getAdapter(config.adapter || (deviceOrConfig && deviceOrConfig.adapter));
  return adapter.writeDevice(deviceOrConfig, maybeConfig, options);
}

function importConfig(rawConfig, options = {}) {
  const adapter = getAdapter(options.adapter || keySilkV1.adapterInfo.id);
  return adapter.importConfig(rawConfig, options);
}

function exportConfig(config) {
  return getAdapter(config.adapter).exportConfig(config);
}

function getLayout(deviceOrConfig) {
  return resolveAdapterForDevice(deviceOrConfig).getLayout(deviceOrConfig);
}

function getBindings(deviceOrConfig) {
  return resolveAdapterForDevice(deviceOrConfig).getBindings(deviceOrConfig);
}

function getCapabilities(deviceOrConfig) {
  return resolveAdapterForDevice(deviceOrConfig).getCapabilities(deviceOrConfig);
}

function getActionBinding(config, actionId, options) {
  return getAdapter(config.adapter).getActionBinding(config, actionId, options);
}

function setActionBinding(config, actionIdOrRequest, bindingId, options) {
  if (typeof actionIdOrRequest === "object") {
    const request = actionIdOrRequest;
    if (request.binding && typeof request.binding === "object") {
      throw new Error(`Structured binding type "${request.binding.type || "unknown"}" is not supported by ${config.adapter} yet`);
    }
    return getAdapter(config.adapter).setActionBinding(
      config,
      request.action,
      request.binding,
      { scope: request.scope, layer: request.layer, ...options },
    );
  }

  return getAdapter(config.adapter).setActionBinding(config, actionIdOrRequest, bindingId, options);
}

function applyBindingModel(config, model) {
  if (model.adapter && model.adapter !== config.adapter) {
    throw new Error(`Model adapter ${model.adapter} does not match config adapter ${config.adapter}`);
  }

  for (const [action, binding] of Object.entries(model.base || {})) {
    if (binding) {
      setActionBinding(config, { scope: "base", action, binding });
    }
  }

  for (const [action, binding] of Object.entries(model.extended || {})) {
    if (binding) {
      setActionBinding(config, { scope: "extended", action, binding });
    }
  }

  for (const hostAction of model.hostActions || []) {
    if (hostAction && hostAction.type === "open_url") {
      setHostOpenUrlAction(config, {
        scope: hostAction.scope || "extended",
        action: hostAction.action,
        url: hostAction.url,
      });
    }
    if (hostAction && hostAction.type === "open_path") {
      setHostOpenPathAction(config, {
        scope: hostAction.scope || "extended",
        action: hostAction.action,
        path: hostAction.path,
      });
    }
    if (hostAction && hostAction.type === "hotkey_open_url") {
      setHotkeyOpenUrlAction(config, {
        scope: hostAction.scope || "extended",
        action: hostAction.action,
        url: hostAction.url,
        binding: hostAction.binding,
      });
    }
    if (hostAction && hostAction.type === "hotkey_open_path") {
      setHotkeyOpenPathAction(config, {
        scope: hostAction.scope || "extended",
        action: hostAction.action,
        path: hostAction.path,
        binding: hostAction.binding,
      });
    }
    if (hostAction && hostAction.type === "hotkey_text") {
      setHotkeyTextAction(config, {
        scope: hostAction.scope || "extended",
        action: hostAction.action,
        text: hostAction.text,
        binding: hostAction.binding,
      });
    }
  }

  for (const macroAction of model.simpleMacroActions || []) {
    if (macroAction && macroAction.type === "simple_macro_taps") {
      setSimpleMacroTapsAction(config, {
        scope: macroAction.scope || "extended",
        action: macroAction.action,
        taps: macroAction.taps,
        label: macroAction.label,
      });
    }
  }

  return config;
}

function setHostOpenUrlAction(config, request) {
  return getAdapter(config.adapter).setHostOpenUrlAction(config, request);
}

function setHostOpenPathAction(config, request) {
  return getAdapter(config.adapter).setHostOpenPathAction(config, request);
}

function setHotkeyOpenUrlAction(config, request) {
  return getAdapter(config.adapter).setHotkeyOpenUrlAction(config, request);
}

function setHotkeyOpenPathAction(config, request) {
  return getAdapter(config.adapter).setHotkeyOpenPathAction(config, request);
}

function setHotkeyTextAction(config, request) {
  return getAdapter(config.adapter).setHotkeyTextAction(config, request);
}

function setSimpleMacroTapsAction(config, request) {
  return getAdapter(config.adapter).setSimpleMacroTapsAction(config, request);
}

function exportHostActionProfile(config) {
  return getAdapter(config.adapter).exportHostActionProfile(config);
}

module.exports = {
  adapters,
  applyBindingModel,
  ...companionRuntime,
  exportHostActionProfile,
  exportConfig,
  getActionBinding,
  getAdapter,
  getBindings,
  getCapabilities,
  getLayout,
  importConfig,
  listAdapters,
  listDevices,
  readDevice,
  setActionBinding,
  setHostOpenPathAction,
  setHostOpenUrlAction,
  setHotkeyOpenPathAction,
  setHotkeyOpenUrlAction,
  setHotkeyTextAction,
  setSimpleMacroTapsAction,
  writeDevice,
};
