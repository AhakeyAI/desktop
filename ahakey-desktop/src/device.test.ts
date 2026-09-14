import { expect, it } from "vitest";
import { deviceConnectionLabel, previewSettings, type HardwareStatus } from "./contracts";
const status: HardwareStatus={batteryLevel:76,signal:50,firmwareMain:1,firmwareSub:0,workMode:3,lightMode:5,lightBrightness:35};
it("USB information is not labeled unready when BLE is absent", () => {
  expect(deviceConnectionLabel({device:{transport:"usb",name:"AhaKey",status},nativeKeyTestEnabled:true})).toBe("USB 已连接 · 语音键已开启");
  expect(deviceConnectionLabel({device:{transport:"ble",name:"AhaKey",status},nativeKeyTestEnabled:false})).toBe("蓝牙 已连接 · 语音键未开启");
  expect(deviceConnectionLabel({device:{transport:null,name:null,status:null},nativeKeyTestEnabled:true})).toContain("等待键盘");
});
it("renderer voice-listener default is on without starting a recording", () => {
  expect(previewSettings.voiceKeysEnabled).toBe(true);
  expect(previewSettings.triggerMode).toBe("hold");
});
it("distinguishes missing USB, failed detection, and failed status without inventing readiness", () => {
  const base = {device:{transport:null,name:null,status:null},nativeKeyTestEnabled:true};
  const usb = {supported:true,present:true,status:null,error:"timeout"};
  expect(deviceConnectionLabel({...base,usb})).toBe("USB 已识别 · 状态读取失败");
  expect(deviceConnectionLabel({...base,usb:{...usb,present:null}})).toBe("本机服务运行 · USB 通信异常");
  expect(deviceConnectionLabel({...base,usb:{...usb,present:false,error:null}})).toContain("等待键盘");
  expect(deviceConnectionLabel({...base,usb,device:{transport:"ble",name:"AhaKey",status}})).toContain("蓝牙 已连接");
});
