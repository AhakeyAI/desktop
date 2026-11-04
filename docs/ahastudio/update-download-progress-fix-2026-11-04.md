# 更新下载进度真实传输修复

2026-11-04提测收口发现：匿名GitHub API实际返回403，公开HTML回退可用。用真实AppUpdateManager源码、正式v0.2.3资产及模拟旧版本0.0.0运行下载（未修改已安装App）后，11,812,986字节完整下载且SHA校验通过，但received/expected/speed全为0。旧手工调用didWriteData的单测不能发现实际回调链断开。

新增本机127.0.0.1慢速TCP/HTTP夹具，512KiB数据分块发送，执行生产下载入口：内容/HTTP成功，而下载中进度、最终字节、总量、速度四个断言全部失败。单纯将委托放到独立session但继续使用async下载接口仍失败；改为完整委托驱动的downloadTask后通过，避免依赖completion-handler路径提供下载进度。

实现保留原URLSession配置及原有可信资产/SHA校验；委托在didFinishDownloadingTo返回前接管临时文件，结束或失败正确释放session；取消前/取消中/重复调用具备隔离和临时文件清理。没有改变自动检测、可用版本提示、安装或打开文件操作，没有新增更新源或自动安装。

## 验证

- 本地真实传输回归先红（4失败）后绿；新增4个回归覆盖下载中进度、取消清理及重复调用隔离。
- 全量1003项Swift测试通过，既有403回退、坏摘要拒绝及AhaType登录/权益路径保留。
- 再以真实生产manager下载公开v0.2.3：检查约7.52秒，下载约6.23秒；received与expected均11,812,986字节，速度非0，摘要匹配GitHub资产。速度字段是采样瞬时速度，不冒称全程平均速度。
- 正式公共DMG仅下载校验后移入本机私有诊断目录，没有安装、没有覆盖候选；实际更新卡片的视觉验收仍待修复候选安装后检查。
- 本机服务夹具仅本机loopback，不使用真实账户/模型；未改系统锁屏设置。测试期间临时防显示休眠断言有时限，收尾需解除。

[Apple下载委托说明](https://developer.apple.com/documentation/foundation/downloading-files-from-websites)用于生命周期参考；具体故障/修复以真实传输回归及[前后回执](../validation/connect-talk-hil-2026-10-22/update-download-progress-2026-11-04.json)为准。原浅层测试仍只支持计算格式，不再单独作为网络集成成功证据。
