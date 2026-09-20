import { describe, expect, it } from "vitest";
import { acceptCaption, previewSettings, sameSettings, mergeSavedDraft, effectiveKeys, mergeIncomingDraft } from "./contracts";

describe("native UI boundary", () => {
  it("adopts tray changes without erasing unrelated pending edits", () => {
    const base=structuredClone(previewSettings);
    const tray={...base,provider:"local" as const,activeProfile:"chatgpt-app"};
    expect(mergeIncomingDraft(base,base,tray)).toEqual(tray);
    const draft={...base,captionBottomOffset:44};
    expect(mergeIncomingDraft(draft,base,tray)).toEqual({...tray,captionBottomOffset:44});
  });
  it("keeps a newer tray selection when an older UI save returns", () => {
    const submitted={...previewSettings,captionBottomOffset:32};
    const newer={...submitted,provider:"doubao" as const};
    expect(mergeSavedDraft(newer,submitted,submitted).provider).toBe("doubao");
    expect(mergeSavedDraft({...newer,captionBottomOffset:20},submitted,submitted).captionBottomOffset).toBe(20);
  });
  it("exposes all four keys and preserves legacy user mappings", () => {
    const profile={...previewSettings.profiles[3],accept:"Tab"};
    const keys=effectiveKeys(profile);
    expect(keys.map(k=>k.action)).toEqual(["voice","shortcut","shortcut","shortcut"]);
    expect(keys[1].shortcut).toBe("Tab");
    keys[3].shortcut="Ctrl+Shift+V";
    expect(effectiveKeys({...profile,keys})[3].shortcut).toBe("Ctrl+Shift+V");
    expect(effectiveKeys(profile)[3].shortcut).toBe("Backspace");
  });
  it("defaults to WeChat and hold, not Windows toggle", () => {
    expect(previewSettings.provider).toBe("wechat");
    expect(previewSettings.triggerMode).toBe("hold");
  });
  it("does not roll back edits or reversions while an earlier save completes", () => {
    const original = structuredClone(previewSettings);
    const submitted = { ...original, captionBottomOffset: 32 };
    const saved = { ...submitted, savedDevice: "device" };
    expect(mergeSavedDraft(original, submitted, saved).captionBottomOffset).toBe(20);
    expect(mergeSavedDraft({ ...submitted, captionBottomOffset: 40 }, submitted, saved).captionBottomOffset).toBe(40);
    expect(mergeSavedDraft(submitted, submitted, saved)).toEqual(saved);
  });
  it("does not replace a new utterance with a delayed previous event", () => {
    const current = {
      phase: "listening" as const,
      text: "new session",
      sequence: 9,
    };
    expect(
      acceptCaption(current, {
        phase: "final",
        text: "old result",
        sequence: 8,
      }),
    ).toBe(current);
    expect(
      acceptCaption(current, {
        phase: "final",
        text: "new result",
        sequence: 10,
      }).text,
    ).toBe("new result");
  });
  it("detects profile edits without changing the stable defaults", () => {
    const copy = structuredClone(previewSettings);
    expect(sameSettings(copy, previewSettings)).toBe(true);
    copy.profiles[3].accept = "Tab";
    expect(sameSettings(copy, previewSettings)).toBe(false);
    expect(previewSettings.profiles[3].accept).toBe("Enter");
  });
});
