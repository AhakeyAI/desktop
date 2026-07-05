const verification = {
  HARDWARE: "hardware",
  OBSERVED: "observed",
  INFERRED: "inferred",
};

function withBindingDefaults(binding, defaults = {}) {
  return {
    verification: verification.INFERRED,
    ...defaults,
    ...binding,
  };
}

function makeBasicKey(id, label, keysilkCode, hidUsage, overrides = {}) {
  return [
    id,
    withBindingDefaults({
      label,
      tail: [0x01, keysilkCode, 0x00, hidUsage],
      category: "basic-key",
      ...overrides,
    }),
  ];
}

function makeShortcut(id, label, keysilkCode, modifierMask, hidUsage, overrides = {}) {
  return [
    id,
    withBindingDefaults({
      label,
      tail: [0x01, keysilkCode, modifierMask, hidUsage],
      category: "shortcut",
      ...overrides,
    }),
  ];
}

const letterBindings = Object.fromEntries(
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("").map((letter, index) =>
    makeBasicKey(letter, letter, 0x0a + index, 0x04 + index, {
      verification: ["A", "B", "C", "Z"].includes(letter) ? verification.HARDWARE : verification.INFERRED,
    }),
  ),
);

const digitBindings = Object.fromEntries(
  ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map((digit, index) =>
    makeBasicKey(`Digit${digit}`, digit, index === 9 ? 0x00 : 0x01 + index, index === 9 ? 0x27 : 0x1e + index, {
      aliases: [digit],
      verification: digit === "0" || digit === "1"
        ? verification.HARDWARE
        : index >= 1 && index <= 7 ? verification.OBSERVED : verification.INFERRED,
    }),
  ),
);

const keySilkShortcutBindings = {
  Ctrl: withBindingDefaults({ label: "Ctrl", code: [0x64, 0x01], category: "shortcut", verification: verification.HARDWARE }),
  Shift: withBindingDefaults({ label: "Shift", code: [0x65, 0x02], category: "shortcut", verification: verification.HARDWARE }),
  Alt: withBindingDefaults({ label: "Alt", code: [0x66, 0x04], category: "shortcut", verification: verification.HARDWARE }),
  Win: withBindingDefaults({ label: "Win", code: [0x67, 0x08], category: "shortcut", verification: verification.HARDWARE }),
  CtrlA: makeShortcut("CtrlA", "Ctrl+A", 0x0a, 0x01, 0x04)[1],
  CtrlC: makeShortcut("CtrlC", "Ctrl+C", 0x0c, 0x01, 0x06, { verification: verification.HARDWARE })[1],
  CtrlV: makeShortcut("CtrlV", "Ctrl+V", 0x1f, 0x01, 0x19, { verification: verification.HARDWARE })[1],
  CtrlX: makeShortcut("CtrlX", "Ctrl+X", 0x21, 0x01, 0x1b)[1],
  CtrlZ: makeShortcut("CtrlZ", "Ctrl+Z", 0x23, 0x01, 0x1d, { verification: verification.HARDWARE })[1],
  CtrlY: makeShortcut("CtrlY", "Ctrl+Y", 0x22, 0x01, 0x1c)[1],
  CtrlS: makeShortcut("CtrlS", "Ctrl+S", 0x1c, 0x01, 0x16)[1],
  CtrlP: makeShortcut("CtrlP", "Ctrl+P", 0x19, 0x01, 0x13)[1],
  CtrlF: makeShortcut("CtrlF", "Ctrl+F", 0x0f, 0x01, 0x09)[1],
  CtrlAltShiftB: makeShortcut("CtrlAltShiftB", "C+A+S+B", 0x0b, 0x07, 0x05)[1],
  CtrlAltShiftC: makeShortcut("CtrlAltShiftC", "C+A+S+C", 0x0c, 0x07, 0x06)[1],
  CtrlAltShiftD: makeShortcut("CtrlAltShiftD", "C+A+S+D", 0x0d, 0x07, 0x07)[1],
  CtrlAltShiftE: makeShortcut("CtrlAltShiftE", "C+A+S+E", 0x0e, 0x07, 0x08)[1],
  CtrlAltShiftF: makeShortcut("CtrlAltShiftF", "C+A+S+F", 0x0f, 0x07, 0x09)[1],
  CtrlAltShiftG: makeShortcut("CtrlAltShiftG", "C+A+S+G", 0x10, 0x07, 0x0a)[1],
  CtrlAltShiftH: makeShortcut("CtrlAltShiftH", "C+A+S+H", 0x11, 0x07, 0x0b)[1],
  CtrlAltShiftI: makeShortcut("CtrlAltShiftI", "C+A+S+I", 0x12, 0x07, 0x0c)[1],
};

const keySilkBasicKeyBindings = {
  ...letterBindings,
  ...digitBindings,
  Esc: makeBasicKey("Esc", "Esc", 0x56, 0x29, { verification: verification.HARDWARE })[1],
  Enter: makeBasicKey("Enter", "Enter", 0x5d, 0x28, { verification: verification.HARDWARE })[1],
  Space: makeBasicKey("Space", "Space", 0x5e, 0x2c, { verification: verification.HARDWARE })[1],
};

const keySilkMediaBindings = {
  Mute: withBindingDefaults({ label: "Mute", tail: [0x06, 0x00, 0xe2, 0x00], category: "media", verification: verification.HARDWARE }),
  VolumeDown: withBindingDefaults({ label: "Volume-", tail: [0x06, 0x01, 0xea, 0x00], category: "media", verification: verification.HARDWARE }),
  VolumeUp: withBindingDefaults({ label: "Volume+", tail: [0x06, 0x02, 0xe9, 0x00], category: "media", verification: verification.HARDWARE }),
  PlayPause: withBindingDefaults({ label: "PlayPause", tail: [0x06, 0x03, 0xcd, 0x00], category: "media", verification: verification.HARDWARE }),
};

const keySilkLayerBindings = {
  NextLayer: withBindingDefaults({ label: "NextScene", tail: [0x0a, 0x00, 0x00, 0x00], category: "layer", verification: verification.HARDWARE }),
  PreviousLayer: withBindingDefaults({ label: "PrevScene", tail: [0x0a, 0x01, 0x01, 0x00], category: "layer", verification: verification.HARDWARE }),
};

const keySilkHostBindings = {
  HostOpenUrl: withBindingDefaults({
    label: "OpenURL",
    tail: [0x04, 0x03, 0xff, 0xff],
    category: "host-action",
    verification: verification.HARDWARE,
  }),
  HostOpenPath: withBindingDefaults({
    label: "OpenPath",
    tail: [0x04, 0x04, 0xff, 0xff],
    category: "host-action",
    verification: verification.HARDWARE,
  }),
};

const keySilkOpenProgramBindings = {
  OpenCalculatorObserved: withBindingDefaults({ label: "Calculator", category: "open-program", verification: verification.OBSERVED }),
};

const keySilkMouseBindings = {
  MouseLeftClick: withBindingDefaults({ label: "LClick", category: "mouse", verification: verification.HARDWARE, mouseButtonMask: 0x01 }),
  MouseRightClick: withBindingDefaults({ label: "RClick", category: "mouse", verification: verification.HARDWARE, mouseButtonMask: 0x02 }),
  MouseMiddleClick: withBindingDefaults({ label: "MClick", category: "mouse", verification: verification.HARDWARE, mouseButtonMask: 0x04 }),
};

const keySilkMouseWheelBindings = {
  MouseWheelUp: withBindingDefaults({ label: "Wheel+1", category: "mouse-wheel", verification: verification.HARDWARE, mouseWheelDelta: 0x01 }),
  MouseWheelDown: withBindingDefaults({ label: "Wheel-1", category: "mouse-wheel", verification: verification.HARDWARE, mouseWheelDelta: 0xff }),
  CtrlMouseWheelUp: withBindingDefaults({ label: "CWh+1", category: "mouse-wheel", verification: verification.HARDWARE, mouseWheelDelta: 0x01, mouseWheelModifier: "ctrl" }),
  CtrlMouseWheelDown: withBindingDefaults({ label: "CWh-1", category: "mouse-wheel", verification: verification.HARDWARE, mouseWheelDelta: 0xff, mouseWheelModifier: "ctrl" }),
};

const keySilkMacroBindings = {
  MacroObserved: withBindingDefaults({ label: "Macro", category: "macro", verification: verification.OBSERVED }),
};

const keySilkTextBindings = {
  TextObserved: withBindingDefaults({ label: "Text", category: "text", verification: verification.OBSERVED }),
};

const keySilkBindings = {
  ...keySilkShortcutBindings,
  ...keySilkBasicKeyBindings,
  ...keySilkMediaBindings,
  ...keySilkLayerBindings,
  ...keySilkHostBindings,
  ...keySilkOpenProgramBindings,
  ...keySilkMouseBindings,
  ...keySilkMouseWheelBindings,
  ...keySilkMacroBindings,
  ...keySilkTextBindings,
};

const actionOrder3Key1Knob = [
  "key1.press",
  "key2.press",
  "key3.press",
  "knob1.rotate_left",
  "knob1.press",
  "knob1.rotate_right",
  "knob1.press_rotate_left",
  "knob1.press_rotate_right",
];

const actionRecordLength = 0x18;
const extendedPointerTableOffsetField = 0x0c;
const extendedPointerTableLength = actionOrder3Key1Knob.length * 4;
const transportPayloadLength = 60;

function readU32LE(buffer, offset) {
  return buffer[offset] | (buffer[offset + 1] << 8) | (buffer[offset + 2] << 16) | (buffer[offset + 3] << 24);
}

function writeU32LE(buffer, offset, value) {
  buffer[offset] = value & 0xff;
  buffer[offset + 1] = (value >>> 8) & 0xff;
  buffer[offset + 2] = (value >>> 16) & 0xff;
  buffer[offset + 3] = (value >>> 24) & 0xff;
}

function padLengthForTransport(length) {
  return Math.ceil(length / transportPayloadLength) * transportPayloadLength;
}

function getRecordOffsets(rawConfig) {
  const declaredLength = readU32LE(rawConfig, 0);
  const offsets = [];
  for (let cursor = 0x30; cursor + 4 <= rawConfig.length; cursor += 4) {
    const offset = readU32LE(rawConfig, cursor);
    if (offset <= 0 || offset >= rawConfig.length) break;
    if (offsets.length && offset <= offsets[offsets.length - 1]) break;
    offsets.push(offset);
    if (offset >= declaredLength) break;
  }
  return offsets;
}

function getExtendedRecordOffsets(rawConfig) {
  const tableOffset = readU32LE(rawConfig, extendedPointerTableOffsetField);
  if (tableOffset <= 0 || tableOffset >= rawConfig.length) {
    return [];
  }

  const offsets = [];
  const tableEnd = tableOffset + extendedPointerTableLength;
  for (let cursor = tableOffset; cursor + 4 <= rawConfig.length && cursor < tableEnd; cursor += 4) {
    const offset = readU32LE(rawConfig, cursor);
    if (offset === 0) {
      offsets.push(null);
      continue;
    }
    if (offset <= 0 || offset >= rawConfig.length) break;
    offsets.push(offset);
  }
  return offsets;
}

function findNextRecordOffset(offsets, start) {
  return offsets
    .filter((item) => item != null && item > start)
    .sort((a, b) => a - b)[0] || null;
}

function getRecordSpan(rawConfig, recordIndex) {
  const offsets = getRecordOffsets(rawConfig);
  const start = offsets[recordIndex];
  if (start == null) {
    throw new Error(`No KeySilk record at index ${recordIndex}`);
  }
  const next = offsets[recordIndex + 1] || start + actionRecordLength;
  const end = Math.min(next, rawConfig.length);
  return { start, end, length: end - start };
}

function getExtendedRecordSpan(rawConfig, recordIndex) {
  const offsets = getExtendedRecordOffsets(rawConfig);
  const start = offsets[recordIndex];
  if (start == null) {
    throw new Error(`No KeySilk extended record at index ${recordIndex}`);
  }
  const nextOffset = findNextRecordOffset(offsets, start);
  const declaredLength = readU32LE(rawConfig, 0);
  const end = Math.min(nextOffset || declaredLength || start + actionRecordLength, rawConfig.length);
  return { start, end, length: end - start };
}

function readUtf16Label(record) {
  const bytes = [];
  for (let i = 2; i < Math.min(record.length, 0x14); i += 2) {
    if (record[i] === 0 && record[i + 1] === 0) break;
    bytes.push(record[i], record[i + 1]);
  }
  return Buffer.from(bytes).toString("utf16le");
}

function writeUtf16Label(record, label) {
  record.fill(0, 2, 0x14);
  const labelBytes = Buffer.from(label, "utf16le");
  if (labelBytes.length > 0x12) {
    throw new Error(`Label too long for current KeySilk record: ${label}`);
  }
  labelBytes.copy(record, 2);
}

function parseRecord(record) {
  return {
    label: readUtf16Label(record),
    typeByte: record[0x14],
    code: [record[0x15], record[0x16]],
    rawTail: Array.from(record.slice(0x14, 0x18)),
    payload: Array.from(record.slice(0x18)),
  };
}

function bindingMatchesRecord(binding, recordBinding) {
  if (!binding || !recordBinding) return false;
  if (binding.tail) {
    return binding.tail.every((value, index) => recordBinding.rawTail[index] === value);
  }
  return recordBinding.typeByte === 0x01
    && recordBinding.code[0] === binding.code[0]
    && recordBinding.code[1] === binding.code[1];
}

function identifyBinding(recordBinding) {
  const hostBinding = identifyHostBinding(recordBinding);
  if (hostBinding) return hostBinding;

  const mouseBinding = identifyMouseBinding(recordBinding);
  if (mouseBinding) return mouseBinding;

  const macroBinding = identifyMacroBinding(recordBinding);
  if (macroBinding) return macroBinding;

  const textBinding = identifyTextBinding(recordBinding);
  if (textBinding) return textBinding;

  for (const [id, binding] of Object.entries(keySilkBindings)) {
    if (bindingMatchesRecord(binding, recordBinding)) {
      return id;
    }
  }
  return null;
}

function identifyHostBinding(recordBinding) {
  if (!recordBinding) return null;
  const tail = recordBinding.rawTail || [];
  if (tail[0] !== 0x04) return null;
  if (tail[1] === 0x03) return "HostOpenUrl";
  if (tail[1] === 0x02) return "OpenCalculatorObserved";
  if (tail[1] === 0x04) return "HostOpenPath";
  return null;
}

function identifyMouseBinding(recordBinding) {
  if (!recordBinding) return null;
  const tail = recordBinding.rawTail || [];
  if (tail[0] === 0x07 && tail[1] === 0x00 && tail[2] === 0x00 && tail[3] === 0x04) {
    const delta = recordBinding.payload && recordBinding.payload[16];
    return {
      0x01: "CtrlMouseWheelUp",
      0xff: "CtrlMouseWheelDown",
    }[delta] || null;
  }

  if (tail[0] !== 0x07 || tail[1] !== 0x00 || tail[2] !== 0x00 || tail[3] !== 0x03) {
    return null;
  }

  const payload = recordBinding.payload || [];
  if (payload[0] === 0xff && payload[1] === 0x00 && payload[6] === 0x01) {
    return "MouseWheelUp";
  }
  if (payload[0] === 0xff && payload[1] === 0x00 && payload[6] === 0xff) {
    return "MouseWheelDown";
  }

  const isMouseClickPayload = payload[0] === 0xff && payload[8] === 0x0c && payload[10] === 0xff;
  if (!isMouseClickPayload) return null;

  const buttonMask = payload[1];
  return {
    0x01: "MouseLeftClick",
    0x02: "MouseRightClick",
    0x04: "MouseMiddleClick",
  }[buttonMask] || null;
}

function identifyMacroBinding(recordBinding) {
  if (!recordBinding) return null;
  const tail = recordBinding.rawTail || [];
  if (tail[0] !== 0x07 || tail[1] !== 0x00 || tail[2] !== 0x00) return null;
  return [0x03, 0x05, 0x06].includes(tail[3]) ? "MacroObserved" : null;
}

function identifyTextBinding(recordBinding) {
  if (!recordBinding) return null;
  const tail = recordBinding.rawTail || [];
  return tail[0] === 0x03 ? "TextObserved" : null;
}

function parseConfig(rawConfig) {
  const offsets = getRecordOffsets(rawConfig);
  const extendedOffsets = getExtendedRecordOffsets(rawConfig);
  return {
    declaredLength: readU32LE(rawConfig, 0),
    rawLength: rawConfig.length,
    records: offsets.map((offset, index) => {
      const next = offsets[index + 1] || offset + actionRecordLength;
      const record = rawConfig.subarray(offset, Math.min(next, rawConfig.length));
      return {
        action: actionOrder3Key1Knob[index] || `unknown.${index}`,
        offset,
        length: record.length,
        binding: parseRecord(record),
      };
    }),
    extendedRecords: extendedOffsets.map((offset, index) => {
      if (offset == null) {
        return {
          action: actionOrder3Key1Knob[index] || `unknown.${index}`,
          offset: null,
          length: 0,
          binding: null,
        };
      }
      const nextOffset = findNextRecordOffset(extendedOffsets, offset);
      const declaredLength = readU32LE(rawConfig, 0);
      const end = Math.min(nextOffset || declaredLength || offset + actionRecordLength, rawConfig.length);
      const record = rawConfig.subarray(offset, end);
      return {
        action: actionOrder3Key1Knob[index] || `unknown.${index}`,
        offset,
        length: record.length,
        binding: parseRecord(record),
      };
    }),
  };
}

function formatBinding(binding) {
  if (!binding) return "(empty)";
  const bindingId = identifyBinding(binding);
  const tail = binding.rawTail.map((value) => value.toString(16).padStart(2, "0")).join(" ");
  return `${bindingId || binding.label || "(unnamed)"} [${tail}]`;
}

function summarizeConfig(rawConfig) {
  const parsed = parseConfig(rawConfig);
  const lines = [
    `declaredLength=${parsed.declaredLength} rawLength=${parsed.rawLength}`,
    "Base records:",
  ];

  for (const record of parsed.records) {
    lines.push(`  ${record.action} = ${formatBinding(record.binding)}`);
  }

  if (parsed.extendedRecords.length) {
    lines.push("Extended records:");
    for (const record of parsed.extendedRecords) {
      if (!record.binding) continue;
      lines.push(`  extended.${record.action} = ${formatBinding(record.binding)}`);
    }
  } else {
    lines.push("Extended records: none");
  }

  return lines.join("\n");
}

function writeBindingToRecord(record, binding) {
  record[0] = 0xff;
  record[1] = 0xff;
  writeUtf16Label(record, binding.label);
  if (binding.tail) {
    record[0x14] = binding.tail[0];
    record[0x15] = binding.tail[1];
    record[0x16] = binding.tail[2];
    record[0x17] = binding.tail[3];
  } else {
    record[0x14] = 0x01;
    record[0x15] = binding.code[0];
    record[0x16] = binding.code[1];
    record[0x17] = 0x00;
  }
}

function resolveAction(actionId) {
  const isExtendedAction = actionId.startsWith("extended.");
  const normalizedActionId = isExtendedAction ? actionId.slice("extended.".length) : actionId;
  const recordIndex = actionOrder3Key1Knob.indexOf(normalizedActionId);
  if (recordIndex < 0) {
    throw new Error(`Unsupported action for current KeySilk 3-key layout: ${actionId}`);
  }
  return { isExtendedAction, normalizedActionId, recordIndex };
}

function resolveBinding(target) {
  const binding = keySilkBindings[target]
    || Object.values(keySilkBindings).find((item) => (item.aliases || []).includes(target));
  if (!binding) {
    throw new Error(`Unsupported binding "${target}". Supported: ${Object.keys(keySilkBindings).join(", ")}`);
  }
  return binding;
}

function buildMouseClickRecord(binding) {
  const record = Buffer.alloc(54, 0);
  record[0] = 0xff;
  record[1] = 0xff;
  writeUtf16Label(record, binding.label);
  record[0x14] = 0x07;
  record[0x15] = 0x00;
  record[0x16] = 0x00;
  record[0x17] = 0x03;
  record[0x18] = 0xff;
  record[0x19] = binding.mouseButtonMask;
  record[0x20] = 0x0c;
  record[0x22] = 0xff;
  return record;
}

function buildMouseWheelRecord(binding) {
  if (binding.mouseWheelModifier === "ctrl") {
    const record = Buffer.alloc(64, 0);
    record[0] = 0xff;
    record[1] = 0xff;
    writeUtf16Label(record, binding.label);
    record[0x14] = 0x07;
    record[0x15] = 0x00;
    record[0x16] = 0x00;
    record[0x17] = 0x04;
    record[0x18] = 0x01;
    record[0x20] = 0x02;
    record[0x22] = 0xff;
    record[0x28] = binding.mouseWheelDelta;
    record[0x2a] = 0x02;
    return record;
  }

  const record = Buffer.alloc(54, 0);
  record[0] = 0xff;
  record[1] = 0xff;
  writeUtf16Label(record, binding.label);
  record[0x14] = 0x07;
  record[0x15] = 0x00;
  record[0x16] = 0x00;
  record[0x17] = 0x03;
  record[0x18] = 0xff;
  record[0x1e] = binding.mouseWheelDelta;
  return record;
}

function resolveBasicKeyUsage(key) {
  const binding = resolveBinding(key);
  if (binding.category !== "basic-key" || !binding.tail) {
    throw new Error(`Macro tap key must be a basic key binding, got "${key}"`);
  }
  return binding.tail[3];
}

function delayToMacroUnit(ms) {
  if (!Number.isInteger(ms) || ms < 0 || ms > 1020 || ms % 4 !== 0) {
    throw new Error(`Macro delay must be an integer 0..1020ms in 4ms units, got ${ms}`);
  }
  return ms / 4;
}

function buildSimpleMacroTapRecord(taps, label = "Macro") {
  if (!Array.isArray(taps) || taps.length < 1 || taps.length > 4) {
    throw new Error("Simple macro taps must contain 1..4 key taps");
  }
  const stepCount = taps.length * 2 + 1;
  const record = Buffer.alloc(0x18 + stepCount * 10, 0);
  record[0] = 0xff;
  record[1] = 0xff;
  writeUtf16Label(record, label);
  record[0x14] = 0x07;
  record[0x15] = 0x00;
  record[0x16] = 0x00;
  record[0x17] = stepCount;

  for (let index = 0; index < taps.length; index += 1) {
    const tap = taps[index];
    const offset = 0x18 + index * 20;
    record[offset] = 0x00;
    record[offset + 1] = resolveBasicKeyUsage(tap.key);
    record[offset + 8] = delayToMacroUnit(tap.delayMs || 0);
  }
  return record;
}

function ensureExtendedTable(rawConfig) {
  const declaredLength = readU32LE(rawConfig, 0);
  const declaredTableOffset = readU32LE(rawConfig, extendedPointerTableOffsetField);
  if (declaredTableOffset) {
    return {
      buffer: Buffer.from(rawConfig),
      tableOffset: declaredTableOffset,
      declaredLength,
    };
  }

  const tableOffset = declaredLength;
  const newDeclaredLength = tableOffset + extendedPointerTableLength;
  const newRawLength = padLengthForTransport(newDeclaredLength);
  const next = Buffer.alloc(newRawLength, 0);
  Buffer.from(rawConfig).copy(next, 0, 0, Math.min(rawConfig.length, next.length));
  writeU32LE(next, extendedPointerTableOffsetField, tableOffset);
  writeU32LE(next, 0, newDeclaredLength);
  return {
    buffer: next,
    tableOffset,
    declaredLength: newDeclaredLength,
  };
}

function replaceExtendedRecord(rawConfig, recordIndex, replacementRecord) {
  const tableState = ensureExtendedTable(rawConfig);
  const source = tableState.buffer;
  const tableOffset = tableState.tableOffset;
  const declaredLength = readU32LE(source, 0);
  const offsets = getExtendedRecordOffsets(source);
  const existingOffset = offsets[recordIndex];
  const oldStart = existingOffset || declaredLength;
  const nextOffset = existingOffset ? findNextRecordOffset(offsets, oldStart) : null;
  const oldEnd = existingOffset ? (nextOffset || declaredLength) : declaredLength;
  const oldLength = oldEnd - oldStart;
  const delta = replacementRecord.length - oldLength;
  const newDeclaredLength = declaredLength + delta;
  const newRawLength = padLengthForTransport(newDeclaredLength);
  const next = Buffer.alloc(newRawLength, 0);

  source.copy(next, 0, 0, oldStart);
  replacementRecord.copy(next, oldStart);
  source.copy(next, oldStart + replacementRecord.length, oldEnd, declaredLength);

  writeU32LE(next, 0, newDeclaredLength);
  writeU32LE(next, tableOffset + recordIndex * 4, oldStart);

  for (let index = 0; index < actionOrder3Key1Knob.length; index += 1) {
    const pointerOffset = tableOffset + index * 4;
    const pointer = readU32LE(next, pointerOffset);
    if (pointer > oldStart) {
      writeU32LE(next, pointerOffset, pointer + delta);
    }
  }

  return next;
}

function ensureExtendedRecord(rawConfig, recordIndex) {
  const declaredLength = readU32LE(rawConfig, 0);
  const declaredTableOffset = readU32LE(rawConfig, extendedPointerTableOffsetField);
  const tableOffset = declaredTableOffset || declaredLength;

  const tableEnd = tableOffset + extendedPointerTableLength;
  const existingOffset = tableOffset + recordIndex * 4 + 4 <= rawConfig.length
    ? readU32LE(rawConfig, tableOffset + recordIndex * 4)
    : 0;

  if (existingOffset) {
    if (existingOffset < tableEnd || existingOffset + actionRecordLength > rawConfig.length) {
      throw new Error(`Invalid KeySilk extended record offset: 0x${existingOffset.toString(16)}`);
    }
    return {
      buffer: Buffer.from(rawConfig),
      span: {
        start: existingOffset,
        end: existingOffset + actionRecordLength,
        length: actionRecordLength,
      },
    };
  }

  const recordOffset = Math.max(declaredLength, tableEnd);
  const newDeclaredLength = recordOffset + actionRecordLength;
  const newRawLength = padLengthForTransport(newDeclaredLength);
  const next = Buffer.alloc(newRawLength, 0);
  Buffer.from(rawConfig).copy(next, 0, 0, Math.min(rawConfig.length, next.length));

  if (!declaredTableOffset) {
    writeU32LE(next, extendedPointerTableOffsetField, tableOffset);
  }
  writeU32LE(next, tableOffset + recordIndex * 4, recordOffset);
  writeU32LE(next, 0, newDeclaredLength);

  return {
    buffer: next,
    span: {
      start: recordOffset,
      end: recordOffset + actionRecordLength,
      length: actionRecordLength,
    },
  };
}

function patchShortcutBinding(rawConfig, actionId, target) {
  const { isExtendedAction, recordIndex } = resolveAction(actionId);
  const binding = resolveBinding(target);

  if (binding.category === "mouse") {
    if (!isExtendedAction) {
      throw new Error(`Mouse bindings require extended scope for current KeySilk firmware: ${actionId}`);
    }
    return replaceExtendedRecord(rawConfig, recordIndex, buildMouseClickRecord(binding));
  }

  if (binding.category === "mouse-wheel") {
    if (binding.mouseWheelDelta == null) {
      throw new Error(`Mouse wheel binding "${target}" is read-only until wheel writes are hardware verified`);
    }
    if (!isExtendedAction) {
      throw new Error(`Mouse wheel bindings require extended scope for current KeySilk firmware: ${actionId}`);
    }
    return replaceExtendedRecord(rawConfig, recordIndex, buildMouseWheelRecord(binding));
  }

  if (binding.category === "macro") {
    throw new Error(`Macro binding "${target}" is read-only until macro writes are fully reverse engineered and hardware verified`);
  }

  if (binding.category === "text") {
    throw new Error(`Text binding "${target}" is read-only until text slot writes are fully reverse engineered and hardware verified`);
  }

  if (binding.category === "open-program") {
    throw new Error(`Open-program binding "${target}" is read-only until standalone program/path writes are fully reverse engineered and hardware verified`);
  }

  const result = isExtendedAction
    ? ensureExtendedRecord(rawConfig, recordIndex)
    : { buffer: Buffer.from(rawConfig), span: getRecordSpan(rawConfig, recordIndex) };
  const next = result.buffer;
  const span = result.span;
  if (span.length !== 0x18) {
    throw new Error(`Unexpected KeySilk record length for ${actionId}: 0x${span.length.toString(16)}`);
  }

  const record = next.subarray(span.start, span.end);
  writeBindingToRecord(record, binding);
  return next;
}

function patchSimpleMacroTaps(rawConfig, actionId, taps, label) {
  const { isExtendedAction, recordIndex } = resolveAction(actionId);
  if (!isExtendedAction) {
    throw new Error(`Macro bindings require extended scope for current KeySilk firmware: ${actionId}`);
  }
  return replaceExtendedRecord(rawConfig, recordIndex, buildSimpleMacroTapRecord(taps, label));
}

function getBindingForAction(rawConfig, actionId) {
  const { isExtendedAction, recordIndex } = resolveAction(actionId);
  const parsed = parseConfig(rawConfig);
  const records = isExtendedAction ? parsed.extendedRecords : parsed.records;
  const record = records[recordIndex];
  if (!record || !record.binding) return null;
  return {
    action: actionId,
    binding: identifyBinding(record.binding),
    raw: record.binding,
    offset: record.offset,
  };
}

module.exports = {
  actionOrder3Key1Knob,
  keySilkBasicKeyBindings,
  keySilkBindings,
  keySilkHostBindings,
  keySilkLayerBindings,
  keySilkMacroBindings,
  keySilkMediaBindings,
  keySilkMouseBindings,
  keySilkMouseWheelBindings,
  keySilkOpenProgramBindings,
  keySilkShortcutBindings,
  keySilkTextBindings,
  verification,
  ensureExtendedRecord,
  getBindingForAction,
  getRecordOffsets,
  getExtendedRecordOffsets,
  identifyBinding,
  parseConfig,
  patchSimpleMacroTaps,
  patchShortcutBinding,
  summarizeConfig,
};
