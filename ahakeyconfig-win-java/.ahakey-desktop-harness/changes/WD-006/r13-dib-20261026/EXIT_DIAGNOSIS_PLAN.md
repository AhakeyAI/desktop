# R13 关闭入口诊断与最小修复方案

依据 OWNER_EXIT_ADDENDUM.json、EXIT_LOG_OBSERVATION.json：现场下载进程已结束；App.allowWindowHide直接因maintenance.active拒绝且无提示，托盘requestClose同样拒绝。FAILED更新窗口却可隐藏，用户失去退出链路入口。不是cleanupConfirmed映射丢失造成：processAlive=false时exitSimple直接结束本次维护。

拟改生产文件：App.java、UpdateCenterService.java、UpdateCenterDialog.java（均现有allowed_paths）。FirmwareUpdateService、INI、worker、固件、协议、OTA保持原样。

方案：UpdateCenterService增加异步关闭准备入口；仅FAILED且simpleActive时在已有单线程worker执行exitSimple，确认IDLE、维护锁释放且无其他忙状态后回调允许关闭。工作进行中/结果未知仍拒绝；不得直接gate.finish、kill或在FX线程等待。App主窗口×与托盘Exit共用此入口，成功后分别执行原收起与真正退出行为；拒绝时显示非阻塞提示并保持窗口可见。更新中心关闭也使用相同准备入口，避免遗留无入口的维护锁。

回归计划：先以生产flashSimple和现场readResult重放创建FAILED/已结束状态，在实际App.allowWindowHide和UpdateCenterService.requestClose上复现拒绝；修复后测实际异步关闭入口，验证已结束失败释放、活进程/未知保持阻止、工作线程清理与快速返回、重复请求不重复动作。用隔离JavaFX窗口验证主窗口处理函数的回调及更新窗口关闭，不启动App.start、Hook、WCH、驱动、网络或设备。所有应用退出清理动作均用无副作用回调观察，不运行真正shutdownApplication。

测试文件拟复用WchAdapterChecks.java（解析）与SimpleFlashChecks.java（关闭/状态回归），隔离UI诊断辅助放target。本文件先供DLA实际方案核对；正式submit前保留两份现场解析回放和新增关闭证据。
