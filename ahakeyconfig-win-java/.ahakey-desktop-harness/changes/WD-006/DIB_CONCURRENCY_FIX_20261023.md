# WD-006 fresh审阅阻断修复

独立审阅发现 VoiceInputManager.onFinal 持有管理器监视锁执行缓慢的 KeyboardInjector.injectText，其他线程同步 F18 startRecording 会等待，可能超过 Windows Hook 超时。

DIB 在原 IMPLEMENT 范围内修复：状态/result/partial外部回调均离开管理器监视锁；最终文本仅在锁内认领一次，完成result回调后重新核对generation并取得injector。该锁内确认是输出提交的线性化点：停用/关闭先取得锁则该结果不输出；输出已提交则可正常完成，不强行中断既有KeyboardInjector。慢输出结束后不允许过期generation再次产生完成状态。初始化与内部状态转换仍串行；没有改变Hook、KeyboardInjector或协议代码。

新增真实并发检查：阻塞输出时其他线程 F18 start/stop、停用和shutdown在500ms等待上限内完成；阻塞result回调时停用成功并使未提交输出保持0次；重复同generation最终回调只注入一次。全生产及测试类重新编译通过，SpeechLifecycleCheck合计37检查通过。日志DIB_LIFECYCLE_20261023_03.log，SHA/实际退出码见同名JSON。没有实际键盘注入/麦克风。

此补充记录替代初轮报告中的VoiceInputManager和SpeechLifecycleCheck当前字节身份；初轮报告及日志保持原样。未submit，等fresh审阅复查；模型资源/EXE由父DLA继续整合。
