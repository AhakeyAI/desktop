# R13 DIB Preview 修复报告

两项原Contract缺陷已修复，待DLA实际diff轻量审阅；没有新候选或新EXE。

## 实际变化（完整delta见R13_DELTA.patch）
- WchFlashAdapter.java：逐个结构化终态校验；固定Programming/Verifing百分比进度作为非终态噪声；错误、非零码、Timeout优先；不跨对象拼字段、不容忍重复键/错类型/嵌套伪成功。
- App.java：主窗口×、最小化、显式Exit共用异步关闭准备；已结束失败收口后保持原行为；未知进程可见拦截，去重提示，最终hide不再延迟到下一FX任务。
- UpdateCenterService.java：prepareWindowClose在既有worker调用exitSimple，windowCloseReady复核；不直接解锁或杀进程。
- UpdateCenterDialog.java：关闭失败窗口也走同一收口，未确认时保持可见且不累计提示。
- WchAdapterChecks.java：真实现场fixture、类型/字段/错误/超时及receipt负例。
- packaging/WindowCloseChecks.java：新增可长期复用隔离FX回归，运行实际App关闭处理函数和更新中心关闭事件。SimpleFlashChecks生产/测试原文件未改，仅复用既有fixture/状态检查。

## 验证
79项终态/回执检查（含两份现场）、19项既有WCH/HEX检查、85项状态及清理检查、23项实际隔离关闭路径检查，共206项通过。
现场旧包readResult两次false；修复回放两次true。旧App.allowWindowHide=false、requestClose=false；已有exitSimple后hide=true。新UI实际X收起且不保留应用退出标记；显式Exit的原requestClose门禁允许；未知子进程被阻止，FX在后台清理期间仍响应，重复点击不重复清理/叠窗，晚到成功回调遇新维护不会隐藏。

仅针对四个生产类及两测试文件JDK17编译；使用R12实际包内JVM/不可变依赖执行。完整命令、退出码、日志和SHA见DIB_REPORT.json。早期辅助探针初始化/参数错误证据保留，最终red-close2与green4/green-close2为有效记录。

## 冻结边界与未验收
其他源码/INI/worker/固件/OTA、冻结实现与R12构建记录、Git HEAD和真实索引均未变。未运行WCH/驱动/安装/真实App.start或shutdown/kill/设备写入。Verifing仅固定工具静态模板证据，仍需Owner实际verify与正常重连版本回读。本轮源码提交后停止修改，下一步DLA审阅后单独派完整本地模型1.0.12 Preview打包。
