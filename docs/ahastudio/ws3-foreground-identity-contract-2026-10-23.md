# WS3 可证明的终端前台身份（开发中）

D02自动前台不能用最近一条Hook、cwd、IDE名称或状态优先级替代会话/窗口关系。本批先补可验证身份与映射，尚未接窗口焦点监测和Agent/App源撤销，不能记为自动前台完整交付。

## 身份与隐私

每次真实Hook在既有sendJsonRequest前读取自身内核BSD进程信息，若确实具有控制终端且属于本用户，附加terminalDevice、terminalGroup、terminalLeaderSeconds、terminalLeaderMicroseconds四个可选字符串字段。原client/session/event及会话SHA引用不变。字段是本机设备号、进程组和leader出生时刻，不记录终端文本、进程名称、命令参数、提示词或工具输入，也不从stdin猜窗口身份。

该信息同步进入既有Agent任务注册表和App短期nonce事件源，旧Hook无字段时保持未知；旧reader可忽略可选字段。WS3ObservedTask增加可选foreground，旧Agent报告仍可解码。不会分配新固件opcode或改变审批。

## 前台映射

注册表接受独立的前台终端身份，只有恰好一个已观察会话具有完全相同的终端设备/组/leader出生时刻，才将该槽foreground置true。多个会话共用进程组、缺少来源、PID被复用、来源消失或断连均不能按最近/状态/槽顺序挑一个。焦点变化不创建任务、不改Hook更新时间，不续300秒TTL；清连接清掉前台事实。

WS3 wire codec仍接受协议合法的多个foreground，不改变协议规则；当前“单个已证实终端焦点”来源最多只能证明一个槽，因此歧义返回零个。

## 原生查询与证据

Xcode SDK的libproc/sys/proc_info.h提供PROC_PIDTBSDINFO、控制TTY e_tdev、TTY前台组e_tpgid和leader出生字段。选中标签的TTY由后续原生窗口来源提供。仅接受/dev/ttys下有界字母数字路径，lstat确认为字符设备，使用PROC_TTY_ONLY最多256个PID的有界查询，读取同用户BSD元数据，核对前台组/leader身份并再次核对样本，数据不足/超限返回未知。

隔离PTY实测发现：父进程打开其他会话的slave后tcgetpgrp返回ENOTTY（25）。客户端因此不打开TTY数据流，使用上述内核筛选路径。正向测试创建自己的临时PTY及C探针，读回设备/组/出生元数据，在子进程存活时与生产captureTTY精确一致；不会打开或读取用户Terminal窗口。

该接口出现在系统SDK头中，但头部注明private interfaces、未来可能变化，不能据此承诺App Store兼容或所有macOS版本均成功；封装失败时保持未知/普通多任务显示，后续旧系统矩阵仍待。窗口/标签自动来源将独立核验，不能仅凭此内核身份宣称已识别当前窗口。

参考：[Apple原生进程实现](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)、[进程字段定义](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/proc_info.h)。本机Terminal.sdef也确认selected tab/tty为只读属性；实际自动化权限及窗口通知尚待消费端接线与验证。

## 局部验证

28项相关测试通过：精确唯一映射、同组多会话不猜、缺失来源/PID复用、断连和TTL不续命、身份编码/非法字段/无关路径拒绝、真实隔离PTY查询，以及现有任务/事件源/协调器回归。测试夹具读管道已改为有界poll/read分片处理，并为写入管道设置F_SETNOSIGPIPE；没有修改全局信号处理。

下一步仍需：可核验的窗口/标签来源；来源存活/权限/退出/睡眠撤销；App/Agent桥接；用户界面整合；GUI客户端无可靠会话API时明确未知；最终自动/真实窗口与OLED验收。没有安装新包或写入键盘。

两轴审查通过。没有将身份/映射基础设施当成窗口焦点来源已实现；后续消费端必须独立验证实际前台窗口及来源存活，并在不能证明时撤销标记。
