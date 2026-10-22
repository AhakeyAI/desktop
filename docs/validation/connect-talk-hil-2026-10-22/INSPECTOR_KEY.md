# 右侧普通键编辑首批候选验收检查点

- 基线connect&talk/b0ce2ea；本批源75a34451fd1ee0f3e61e12306421adf4683e3a5c。
- 388项自动测试通过；Standards与Spec初审共3项P2，均修复并窄复核通过（queued旧任务、新鲜非规范动作只读、宏动作差异展示）。
- 本机签名0.2.3 arm64候选已安装，deep/strict通过，Info.plist AhaKeyGitCommit为75a3445。
- 旧包备份：本机local-backups/studio-before-inspector-session-20261022/AhaKey Studio.app。

## 已观察

启动候选，首页连接AhaKey505C、42%/自动批准、原生转写桥4/4运行。选中虚拟Key4后显示Mode3/Backspace、未同步0。准备从右侧“修改”进入新会话。

点击修改的调用返回“Sky Computer Use native pipe closed before response”，重置工具后getApp仍失败，无法确认点击是否实际生效或读取是否完成。没有继续按键写入、素材写入、Voice重绑或刷机。不将工具错误归为App故障。

独立读取Agent socket后确认：presentation_tasks.connected=true、presentationBusy=false；approval_status.physicalSwitchState=0、switchState=0、approvalAutoVerified=true。日常后台连接有效，但这不替代右侧UI读取/保存验收。

## 待继续

已请求用户重开Codex恢复界面服务。恢复后先重新读当前UI：
1. 从虚拟Key4→修改完成读回并自动交还Agent，保持编辑态。
2. 修改一项可恢复描述、保存此键、读回、还原原描述；其他模式/键位、Voice、Coffee不变。
3. 验证同值不声明新保存/不清未确认；返回未写草稿保留；可以的话受控冲突与取消。
4. 最终返回日常Agent，记录UI/RPC，补截图及WBS；未验收前PR保持草稿，不合入。

未知/旧设备、真实故障、Consumer混用、灯条/素材迁入仍是后续工作，不能因本批代码和编译通过标记完整适配完成。


## 用户重开Codex后的续验

用户确认已重开。原生getApp仍报pipe closed；reset后getState能读取应用清单，但通过bundleID（多个历史包歧义）及精确安装路径重新绑定仍不能读取原生窗口。没有要求用户再次重开，也没有改用其他UI自动化技术绕过。

已改请用户手动选Codex Key4→修改、只读核对右侧显示，不保存；等待反馈。fresh后台RPC仍connected=true、physical/effective=0、autoVerified=true；PR153当前3c5f450四项CI均成功，但手动/自动UI验收未完成，仍保持草稿。

等待期间完成V10静态核验，见consumer-per-mode-feasibility-2026-10-22.md；未修改Voice、其他按键或固件。


## 首次手动读取反馈与精简候选

用户确认“读回正常”，未报告跳页；但指出信息过于复杂，要求放在按键描述下方。该反馈仅证明读取入口，不代替真实保存/还原验收。已据此精简读回区，待新候选安装与继续验收；原生自动控制仍不可用。

### 精简版已替换安装

用户确认退出Studio后已备份75a3445，替换签名0.2.3 arm64/5af66052ba464236ea33ea7264cb3e32e3dbfb7e；安装路径deep/strict及来源核对通过。7项摘要/单键事务相关测试和两轴窄复核通过。本次布局调整不新增硬件行为测试，未宣称重跑全部388项。

因原生控制仍不可用，已请用户打开新包，确认按键描述下“已读取：Backspace”+刷新图标的布局。尚待该反馈；没有真实按键写入、Voice改绑或素材写入。后续仍需单键保存/还原和日常Agent确认，PR153保持Draft。


### 主键下方统一说明

用户人工确认5af6605精简版正常展示，进一步要求移到主键下方，按读回→保存前核对说明→LCD描述说明排序。本次仅布局，待新候选构建/替换后再确认；尚未执行单键真实写入/还原，不因布局通过宣称事务HIL完成。

### dbea629安装与原生服务崩溃定位

用户确认退出后，已备份5af包到studio-before-inspector-primary-20261022，替换/Applications为签名0.2.3/dbea62996d976745e5f02eacab0be0208a7f32c6，deep/strict及来源核对通过。

用户要求由Agent修复控制服务，不再不断代点。重新绑定普通首页成功、选Key4成功；点击右侧修改并读取后再次pipe closed。原生完整AX（disableDiffing=true）和截图入口均失败。最新5份SkyComputerUseService .ips均EXC_BREAKPOINT/SIGTRAP，栈顶_assertionFailure/Array.remove，前几帧imageOffset相同。控制辅助App签名验证通过；尚未定位具体控件或服务源码缺陷，不能称已永久修复。普通界面暂时恢复不代表编辑界面恢复。

原生控制服务崩溃后拒绝对未成功读取的App继续发操作，CmdQ也被拒绝；因此已请求一次明确授权，允许AppleScript仅用于退出/重开Studio及该窗口排查/验收。CUA规则要求其他UI技术由用户明确指定，获得答复前不执行替代UI操作。没有改系统权限、覆盖原生服务二进制、杀其他会话或发送外部报告。

私有证据local-backups/cua-service-diagnosis-20261022含5份原始ips及摘要。fresh Agent仍connected=true、physical/effective=0、autoVerified=true。真实单键保存/还原仍未执行，PR保持草稿。


## 本轮最终结果

用户授权AppleScript后已自动恢复测试环境；确定默认GroupBox标题的无障碍结构触发原生控制服务崩溃，最终d2345a2改显式文本分组，原生按键/宏/长按/屏幕编辑恢复。原位Key4描述临时写入TestBack→新连接读回→恢复Backspace→同值不写已通过，无遗留测试改动。详细证据和边界见CONTROL_SERVICE_RECOVERY.md；前文等待/断管是历史检查点，不再要求用户代点或重复退出安装。
