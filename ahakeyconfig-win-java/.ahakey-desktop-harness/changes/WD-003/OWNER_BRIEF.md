# WD-003 Owner 测试简报

**交测条件核对完成；设备步骤仍须先确认实机身份**


## 这次测什么

WD-003：用正式JAR与当前CP4D固件验证0x9F能力读取、0x95睡眠等待时间读回保留、0x97侧拨配置读回/保存校验、0x87普通键单包读回、侧拨Custom单键/组合快捷键/短宏保存读回，以及普通键K1-K4默认配置读回不被破坏。

入口：AhaKey Studio主界面 -> 键盘画布K1-K4与侧拨部件 -> 右侧Inspector；More/Hawk设备信息区域用于0x95睡眠等待时间回归核对。

交付形式：jar_classpath；产品发行版：shared-source

JAR 结果只覆盖这份 JAR/config；不代表轻量EXE、带模型EXE、安装切换或发布通过。


## Windows 文件与启动

工作目录：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`

主产物：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\builds\WD-003\20261008T005913928548Z-cecb3e\runtime\ahakey-studio-1.0.0.jar`

SHA256：`52a79397c28529203c777b594555947bdba4822e004d6179d4b9ead03c59a43b`

实际模型配置：shared JAR / local model disabled

配套输入／运行依赖：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\builds\WD-003\20261008T005913928548Z-cecb3e\runtime\ahakey-studio-1.0.0.jar`, `C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\builds\WD-003\20261008T005913928548Z-cecb3e\runtime\lib`

产物存在与打包成功不代表已经启动成功。

本次直接运行 JAR，不安装新版 EXE。

启动方式（DLA核对后的实际配方，不由Harness猜测）：

```powershell

Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\builds\WD-003\20261008T005913928548Z-cecb3e\runtime'; & 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -cp 'ahakey-studio-1.0.0.jar;lib\*' com.example.ahakey.Main

```


## Firmware 原件（只读引用）

来源：Firmware Harness 已有候选；Windows 不生成 HEX、不自动烧录。

硬件：X1 / CP4D ordinary-key readback test unit; physical unit identity must be confirmed by Owner before executing device steps

固件说明：WS2 CP4D ordinary-key readback candidate at firmware commit 8167ba13049c781da2f975bc803eccfe0e6ea2aa

HEX 完整路径：`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws2-cp4d-ordinary-key-readback\HID_Keyboard_582m_vibe_coding.hex`

SHA256：`6f9759eb912ec067564c4e63558589ab9732126344d52c2d2a278383119516be`

正式Gate：`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\checkpoints\X1-INPUT-CONTROL\CP4D\20261007T131850\gate-receipt.json`

候选提交：`8167ba13049c781da2f975bc803eccfe0e6ea2aa`

物理设备是否已刷此HEX：必须由Owner确认，文件hash不能证明已烧入。


## 前置条件

使用正式runtime JAR SHA256 52a79397c28529203c777b594555947bdba4822e004d6179d4b9ead03c59a43b，并保留runtime/lib中17个依赖JAR。设备步骤前，Owner必须确认手上的X1已刷入CP4D HEX SHA256 6f9759eb912ec067564c4e63558589ab9732126344d52c2d2a278383119516be。此前Owner Preview PASS只说明预览通过，不是formal UAT。

连接方式：使用现有正常USB或BLE连接路径，Owner记录实际连接方式。本交测资料不安装驱动、不杀进程、不自动连接设备、不写固件、不烧录。


## 操作与预期

### T01 · 启动与产物身份

在runtime目录用上面的PowerShell命令启动这份正式JAR，先不操作键盘。

**预期：** 应用正常打开；如果出现JavaFX、依赖、入口或路径错误，停止并回传完整终端输出。仅启动不等于设备行为通过。

结果填写：通过／失败／未执行。

### T02 · 设备与固件身份

通过正常USB或BLE路径连接目标X1，并确认物理设备已刷入FIRMWARE_IDENTITY.json记录的CP4D HEX。

**预期：** 设备连接成功，Owner明确确认物理设备/HEX身份；未确认前不执行会写入设备配置的步骤。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T03 · 0x9F能力读取

连接后确认Windows执行0x9F能力/目录读取，并判断是否属于CP4C/CP4D允许列表。

**预期：** CP4C/CP4D catalog key被读取并接受；如果0x9F缺失、失败或返回非允许key，Windows保持legacy行为，不使用0x87或可编辑0x97。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T04 · 0x95回归

打开现有睡眠等待时间区域，读取当前0x95睡眠等待时间值。

**预期：** 现有0x95读回仍正常，显示合法值或明确读失败；WD-001睡眠等待时间能力没有被WD-003破坏。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T05 · 0x97侧拨读回

点击键盘画布上的侧拨部件，查看右侧Inspector中的上下位置配置和物理位置。

**预期：** 侧拨配置来自0x97读回，上下位置、Auto/Manual/Disabled/Custom显示一致，物理位置显示仍可见。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T06 · 0x87当前模式K1-K4读回

连接/读回后观察当前模式K1-K4。

**预期：** K1-K4从0x87设备基线显示，包括默认或空配置；普通键默认配置读回没有被破坏。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T07 · 0x87后台全量读回

切换四个模式并等待后台读回完成，观察每个模式的K1-K4。

**预期：** 四个模式共16个普通键通过0x87读回；当前模式快速显示，已读模式再次切换时不显示陈旧本地默认值。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T08 · 侧拨Custom单键

把一个侧拨位置设为Custom单键快捷键，例如Backspace，保存后重新读回。

**预期：** Windows通过0x97写入并再读0x97；只有读回匹配时才显示保存成功。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T09 · 侧拨Custom组合快捷键

把一个侧拨位置设为Custom组合快捷键，例如Ctrl+V，保存后重新读回。

**预期：** 组合快捷键按shortcut payload保存并精确读回，不变成裸HID keycodes。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T10 · 侧拨Custom短宏

把一个侧拨位置设为短宏，保存后重新读回；如安全且方便，可尝试超长宏限制提示。

**预期：** 短宏保存并读回一致；超长宏在成功前被阻止、禁用或清楚提示，不能静默截断后宣称成功。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T11 · 普通键保存读回校验

编辑当前模式一个普通键（例如K1），通过现有保存流程保存，再用0x87读回受影响键。

**预期：** 普通键仍走既有0x73/0x04写入/持久化路径；只有受影响键0x87读回与保存草稿匹配时才显示保存成功。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T12 · 失败与断连行为

通过保存前断连、自然读回失败或可观察的不匹配场景核对失败行为；不要为了失败测试猜协议字节。

**预期：** Windows显示轻量失败/禁用状态，保留未确认草稿，不宣称保存成功，并在日志中提供catalogKey/cmd/mode/keyIndex/phase/reason等线索。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。

### T13 · legacy回退

如果有legacy或非CP4C固件设备，连接后检查普通键和侧拨行为；没有此设备时如实记为未执行。

**预期：** legacy固件保持旧普通键本地行为，隐藏可编辑0x97，不调用0x87；无legacy设备时不得伪造PASS。

结果填写：通过／失败／未执行。设备步骤：确认硬件/固件后再执行。


## 合同验收覆盖（不是执行结果）

- A001：- Project compiles. → existing_evidence；Formal build log records the project packaging successfully under JDK17.

- A002：- Focused unit/helper tests if added. → existing_evidence；DIB revalidation captured the focused Windows checks for this implementation identity.

- A003：- No use of `0x98` for ordinary-key readback. → existing_evidence；The revalidation evidence explicitly covered the no-0x98 ordinary-key readback requirement.

- A004：- Legacy firmware path does not call `0x87`/editable `0x97`. → planned_owner；T03,T13

- A005：- CP4C firmware connects and performs background full input readback. → planned_owner；T02,T03,T07

- A006：- Current mode appears quickly; other modes are ready after background read. → planned_owner；T06,T07

- A007：- Editing ordinary keys saves only after `0x87` readback matches. → planned_owner；T11

- A008：- Editing side switch saves only after `0x97` readback matches. → planned_owner；T08,T09,T10

- A009：- A readback mismatch/failure shows lightweight UI notice, Inspector failure state, and logs enough evidence. → planned_owner；T12

- A010：- Legacy firmware keeps old ordinary-key and side-switch behavior. → planned_owner；T13


## 停止与恢复

修改普通键或侧拨前先记录当前可见配置；测试后按需恢复。启动、连接、读回、保存、比对、断连或日志收集失败时，停止受影响子项，保留截图、终端输出和logs/ahakey-studio.log，不用界面状态推断设备已成功保存。


## 本轮不代表什么

本轮不验证轻量EXE、带模型EXE、安装包切换、发布包、全量产品回归、Firmware release、CP5、灯光、OLED/GIF/图片、语音、电源、恢复出厂、HID描述符或固件升级/恢复。


## 你怎样反馈

按T01-T13逐项回传通过/失败/未执行，注明实际USB/BLE路径和固件身份确认；侧拨、K1-K4读回和失败场景请附截图，失败请附logs/ahakey-studio.log与终端输出。


本轮Agent已经做过的机器检查见构建/审阅回执；本简报生成没有启动程序、访问设备或执行测试。

Owner UAT：尚待真实反馈。Git、安装切换和发布权限不因生成简报而扩大。
