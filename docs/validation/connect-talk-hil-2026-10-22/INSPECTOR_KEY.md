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
