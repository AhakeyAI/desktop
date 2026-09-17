import { expect, it } from "vitest";
import { reportedHostLabel } from "./routing";
it("keeps unknown, unreported and client-reported host identity distinct", () => {
  expect(reportedHostLabel(undefined)).toBe("设备名称未读取");
  expect(reportedHostLabel({name:null,system:null})).toBe("名称未上报");
  expect(reportedHostLabel({name:null,system:"macOS"})).toBe("主机名未知 · macOS");
  expect(reportedHostLabel({name:"开发电脑",system:"Windows"})).toBe("开发电脑 · Windows");
});
