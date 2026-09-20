import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const read = (path) => readFileSync(new URL(path, import.meta.url));
describe("macOS icon packaging", () => {
  it("uses an app bundle command and real platform icon assets", () => {
    const config = JSON.parse(read("../src-tauri/tauri.conf.json").toString());
    const mac = JSON.parse(read("../src-tauri/tauri.macos.conf.json").toString());
    const pkg = JSON.parse(read("../package.json").toString());
    expect(pkg.version).toBe(config.version);
    expect(pkg.scripts["desktop:bundle"]).toContain("--bundles app");
    expect(pkg.scripts["desktop:bundle"]).not.toContain("--no-bundle");
    expect(mac.bundle.active).toBe(true);
    expect(mac.bundle.targets).toEqual(["app"]);
    expect(config.bundle.icon).toContain("icons/icon.icns");
    const icns = read("../src-tauri/icons/icon.icns");
    expect(icns.subarray(0, 4).toString()).toBe("icns");
    expect(icns.readUInt32BE(4)).toBe(icns.length);
    const png = read("../src-tauri/icons/icon.png");
    expect([...png.subarray(0, 8)]).toEqual([137,80,78,71,13,10,26,10]);
    const plist = read(`../src-tauri/${mac.bundle.macOS.infoPlist}`).toString();
    expect(plist).toContain("NSMicrophoneUsageDescription");
    expect(plist).toContain("NSBluetoothAlwaysUsageDescription");
  });
});
