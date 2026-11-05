# WD-010 R3 独立复审执行证据

结论：PASS，仅绑定冻结包 `c86361128abf1edad99e937549c6f7ba4cb5901f17360850624ed4350ac4688f` 的代码审阅。正式结论见 FINAL_REVIEW_R3.json。

原始复现fixture SHA256 `143a5d0c07f5c44053de89fd22983fc72c5c18716a5e18fe7dced2ea8f77ad13`，与第2轮原字节一致；源码已归档在第2轮DETAILS中。第2轮同一fixture两条路径失败；本轮两条均通过。

快照清单：`C:\Users\20825\AppData\Local\Temp\wd010-fresh-r3-x6ahs7l5\SNAPSHOT.json`，SHA256 `781012c0fd6e099b3e377f4054430ffcbaaa467ebef0ff65fa0e4001931e366b`。生产类没有重新编译；原始fixture单独编译，和提交的84项fixture分别使用隔离home并运行。没有实际账号、付款或设备动作。

```json
[
  {
    "suite": "QueuedDeliveryChecks84",
    "command": [
      "D:/jdk-17.0.19.10-hotspot/bin/java.exe",
      "-Dfile.encoding=UTF-8",
      "-Duser.home=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\home-QueuedDeliveryChecks84",
      "-Djava.io.tmpdir=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5",
      "-cp",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\test-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\lib\\*",
      "com.example.ahakey.wd010.CheckProcess",
      "com.example.ahakey.service.QueuedDeliveryChecks"
    ],
    "cwd": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5",
    "exit_code": 0,
    "log": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\QueuedDeliveryChecks84.log",
    "sha256": "cfb0cb0bd8c09e5b116b4c05f79233215662d3186a15632ffd17b30de879b37a"
  },
  {
    "suite": "OriginalQueuedDeliveryReproduction",
    "command": [
      "D:/jdk-17.0.19.10-hotspot/bin/java.exe",
      "-Dfile.encoding=UTF-8",
      "-Duser.home=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\home-OriginalQueuedDeliveryReproduction",
      "-Djava.io.tmpdir=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5",
      "-cp",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\original-repro-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\test-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\lib\\*",
      "com.example.ahakey.wd010.CheckProcess",
      "com.example.ahakey.service.QueuedDeliveryChecks"
    ],
    "cwd": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5",
    "exit_code": 0,
    "log": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r3-x6ahs7l5\\OriginalQueuedDeliveryReproduction.log",
    "sha256": "c504e301b3d92272ae0aded10473f40d092615c471d168eb6bb6f6462871be81"
  }
]
```

## QueuedDeliveryChecks84

```text
11月 05, 2026 5:32:32 下午 com.sun.javafx.application.PlatformImpl startup
警告: Unsupported JavaFX configuration: classes were loaded from 'unnamed module @31221be2'
coupon queued result scenario=server_expiry PASS
coupon queued result scenario=logout PASS
coupon queued result scenario=switch_account PASS
coupon queued result scenario=close_dialog PASS
coupon queued result scenario=hide_reopen_coupon PASS
payment queued result scenario=server_expiry PASS
payment queued result scenario=logout PASS
payment queued result scenario=switch_account PASS
payment queued result scenario=close_dialog PASS
payment queued result scenario=close_payment PASS
payment queued result scenario=close_reopen_payment PASS
PASS QueuedDeliveryChecks 84 checks; real queued FX transaction callbacks, loopback only

```

## OriginalQueuedDeliveryReproduction

```text
11月 05, 2026 5:32:32 下午 com.sun.javafx.application.PlatformImpl startup
警告: Unsupported JavaFX configuration: classes were loaded from 'unnamed module @377dca04'
coupon success callback was queued; server expiry mapping valid; terminalShown=true; labels= | 当前账号：fixture | 兑换成功；登录已失效，请重新登录
payment success callback was queued; server expiry mapping valid; terminalShown=true; labels= | 金额：1.00 元（所选套餐报价） | 支付成功；登录已失效，请重新登录
PASS QueuedDeliveryChecks

```
