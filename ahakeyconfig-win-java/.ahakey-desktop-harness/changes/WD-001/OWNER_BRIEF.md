# WD-001 Owner 测试简报

**交测条件核对完成；设备步骤仍须先确认实机身份**


## 这次测什么

WD-001：CP3A睡眠等待时间的读取、设置、确认、回读、持久化及合同内回归；当前仅JAR联调。

入口：More → Hawk 安装分发工具 → 第一个“设备信息”卡片 → 睡眠等待时间

交付形式：jar_classpath；产品发行版：shared-source

JAR 结果只覆盖这份 JAR/config；不代表轻量EXE、带模型EXE、安装切换或发布通过。


## Windows 文件与启动

工作目录：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`

主产物：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\ahakey-studio-1.0.0.jar`

SHA256：`c16f5bad0f518fb8fea00f7dee7f97caaf7ac6dc3865092442a2bee260217886`

实际模型配置：shared JAR / local model disabled

配套输入／运行依赖：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target`

产物存在与打包成功不代表已经启动成功。

本次直接运行 JAR，不安装新版 EXE。

```powershell

Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java'

& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -version

& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -jar 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\ahakey-studio-1.0.0.jar'

```


## Firmware 原件（只读引用）

来源：Firmware Harness 已有候选；Windows 不生成 HEX、不自动烧录。

硬件：X1 / CP3A test unit; physical unit identity must be confirmed by Owner before executing device steps

固件说明：CP3A candidate at firmware commit a9db65e2e73bc56b669c312e9fc42f3ee02c3d49

HEX 完整路径：`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws1-cp3a-host-configurable-quiet-sleep-timeout\HID_Keyboard_582m_vibe_coding.hex`

SHA256：`9aabce5f015fd44d980ff6818d825b6bab34f6e4b4f7ac277e942272d700444c`

正式Gate：`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\checkpoints\X1-CONNECTIVITY-POWER\CP3A\20260928T164837\gate-receipt.json`

候选提交：`a9db65e2e73bc56b669c312e9fc42f3ee02c3d49`

物理设备是否已刷此HEX：必须由Owner确认，文件hash不能证明已烧入。


## 前置条件

核对JAR与运行依赖未变；先确认目标X1已刷本次固件。未确认设备身份不得写设置。当前未执行应用/UI/设备测试。

连接方式：使用现有正常测试连接，Owner记录实际USB或BLE；本包不安装或启动驱动。


## 操作与预期

### T01 · 应用启动前置核验

在当前目录用指定JDK17启动这份JAR，保留target/lib，先不操作键盘。

**预期：** 窗口正常打开；如报JavaFX、依赖或入口错误，停止并回传完整终端输出。仅打开不等于已验证设备。

结果填写：通过／失败／未执行。

### T02 · 测试设备固件身份确认

确认手中是目标X1，且已刷入本简报所列CP3A HEX；使用已配置的USB或BLE连接方式，并记录实际方式。不确定已刷版本时先停止设备写入。

**预期：** 设备身份由Owner确认，不由HEX文件存在推断；连接状态正确。无需为了确认而自动重复烧录。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T03 · 现有配置值读取记录

More → Hawk 安装分发工具 → 第一个设备信息卡片，查看“睡眠等待时间”并记录原始值。

**预期：** 显示永不/30/60/120中的当前值；异常或读取失败明确显示，不假成功；未新增卡片。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T04 · 三十分钟保存与即时回读

选择30分钟并点击本项保存，观察保存中/结果提示，再读取当前设置。

**预期：** 只有0x95 set→OK→query回读30匹配才显示成功；本项不追加0x04。界面变化本身不证明设备应用，需对应实际回读。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T05 · 断电重启后的持久化核验

按固件认可的真正重启/断电方法重启键盘，重新连接查询；不要用关闭软件代替断电。

**预期：** 仍为30；记录操作方法。USB仍供电的假关机不能自动算掉电持久化。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T06 · 其余合法值完整验证

依次设置永不(0)、60、120，每个值按本项合同做设置/立即回读/真正重启后回读，记录结果。

**预期：** 每值正确，重启后保留；0代表不自动Quiet/Sleep。每个值未测的部分如实写未执行。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T07 · 受控非法值负向验证

只在已有受控协议/固件测试工具且具体用法明确时测试非法0x95值；普通UI不新增非法输入。缺工具时写未执行并报告，不临时猜字节或下载工具。

**预期：** 返回失败，查询原值未改变。此项来自合同，不因UI仅有合法值而自动免测；可以引用经核对适用证据或Owner明确后置决定。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T08 · 真实空闲睡眠唤醒观察

按选定的真实等待时间和固件的空闲条件观察Quiet/Sleep，再唤醒；保持本项条件，不为加速擅自改固件。记录实际等待、屏幕/状态/按键/连接。

**预期：** 按配置进入睡眠，唤醒恢复正确，无自动反复醒来、黑屏或display loop。即时保存成功不能覆盖此项，未等待则写未执行。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T09 · 相关电源生命周期回归

按固件已有安全UAT说明检查合同列出的Power短/长按、Forget guard、USB fake-off、true-off USB插入、single-host reconnect、USB/Mac wired lifecycle。仅有合适硬件/环境时执行，缺项明确记录或引用适用证据。

**预期：** 各子项符合既定行为，未引入回归；不存在或不适用的环境不伪造PASS，也不因此改Windows/Firmware代码。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T10 · 界面保留与断连行为核对

查看同卡片连接、电量/设备名/拨杆以及原More行为；断连后查看本项控制。不要点击安装Hook/驱动来代替观察。

**预期：** 已有显示和入口保持；断连时本项禁用或提示先连接，不能显示设备保存成功。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T11 · 结果记录与原值恢复

记录测试结果，按需要把睡眠等待时间恢复到T03原值；若已发生失败，先保留现场与日志，停止受影响子项。

**预期：** 恢复结果可确认；测试记录区分通过/失败/未执行，没有把恢复动作当成所有验收通过。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。


## 合同验收覆盖（不是执行结果）

- A001：- Java 17 Maven 编译通过。 → existing_evidence；已有DIB机器编译证据适用于当前code_fingerprint/build_round；本轮未重跑构建。

- A002：- 静态核对：睡眠等待时间保存路径不发送 `0x04 save_config`。 → existing_evidence；已有静态回归证据明确核对睡眠等待时间路径不发送0x04 save_config。

- A003：- UI 静态核对：入口位于 More 弹窗第一个“设备信息”卡片内，没有新增卡片。 → existing_evidence；已有静态回归证据核对UI插入位置为More弹窗第一个设备信息卡片且未新增单独卡片。

- A004：- 烧录指定 CP3A HEX，并确认 SHA256 为 `9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C`。 → planned_owner；T02

- A005：- 上位机查询 `0x95`，记录当前睡眠等待时间。 → planned_owner；T03

- A006：- 设置 30，收到 `0x95 OK` 后立刻查询，确认回读是 30。 → planned_owner；T04

- A007：- 断电/重启键盘，再查 `0x95`，确认仍是 30。 → planned_owner；T05

- A008：- 同样测试 0 / 60 / 120；其中 0 表示永不自动进入 Quiet/Sleep。 → planned_owner；T06

- A009：- 发送非法值，确认返回失败，并且原值不变。 → planned_owner；T07

- A010：- 确认上位机不需要再发 `0x04 save_config`。 → planned_owner；T04

- A011：- 测 Sleep/Wake / real Sleep / display loop：休眠后唤醒，屏幕亮、状态正确、按键/连接恢复，不能出现自动反复醒来或黑屏循环。 → planned_owner；T08

- A012：- 快速烟测 WS1 生命周期：Power 短按/长按、Forget guard、USB fake-off、true-off USB 插入、single-host reconnect、USB/Mac wired lifecycle。 → planned_owner；T09


## 停止与恢复

先记录原值，测试结束按需恢复。启动或设备步骤失败，停止对应子项并保留PowerShell输出、截图和logs/ahakey-studio.log，不自动reset/clean/烧录。


## 本轮不代表什么

不代表轻量EXE/带模型EXE、安装切换、语音质量、全设备兼容或官网发布通过。不修改原键位/OLED/其它保存语义。


## 你怎样反馈

用自然语言、截图/日志回传每个T编号及其子项通过/失败/未执行；注明实际连接和设备固件确认。DLA负责结构化，不能代填。


本轮Agent已经做过的机器检查见构建/审阅回执；本简报生成没有启动程序、访问设备或执行测试。

Owner UAT：尚待真实反馈。Git、安装切换和发布权限不因生成简报而扩大。
