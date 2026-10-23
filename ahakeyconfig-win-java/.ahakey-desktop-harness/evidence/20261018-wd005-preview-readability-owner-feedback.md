# WD-005 Preview 可读性失败与最小退修

日期：2026-10-18。原DLA对话Owner请求：
> 首先测下来，这个框里面的文字是白色的，完全看不清。然后所有的日志这会都是乱码，不好观察，其他的我还没有具体的测试。你先把这个两个点，短平快修改一下，然后我再具体测试

## 身份与观察

Preview token：preview-20261017T104547091113Z-0e6fcf。
JAR SHA256：e8bbe9ee0dc3da54733d057c4bc2ab6ee8d12fa9bdc333290b4947f055e752e5。
截图：C:/Users/20825/AppData/Local/Temp/codex-clipboard-5fb045e8-02cb-445d-b89c-0dd9b8e03c82.png；SHA256 E07D81EA4FED90AA98179BF5B307B1DFF5097757E979FA5FC51A32F36D9DF376。
补充终端原文：C:/Users/20825/.codex/attachments/09553011-651a-41cb-a9dd-60c2472d7ec6/已粘贴的文本.txt；SHA256 0622112E98340CA2F384A69E587EA38AF6BDADCCB6BE537EF402BE82DDE95F6A。

截图确认浅底OLED资源框中的标题/状态/帧数为白字，不可读。离线禁用上传按钮本身不是本问题，不能通过取消禁用修复对比度。
终端粘贴中文乱码；但DLA用Get-Content -Encoding UTF8读取同令牌runtime-jar-classpath/logs/ahakey-studio.log，14:57:15启动、语言设置、模型配置等同一时刻中文正常。可确认文件日志样本正常，控制台乱码；不声称已检查所有历史日志。文件中的USB HID connected、0x9F/0x98 ACK不代表全部设备验收，其他功能按Owner原话未具体测试。

## 分类及修复范围

属于原合同A09界面可读性及A11可观察日志/启动配方的实现/交付缺陷，走Preview快修，不重新Grill，不重做合同或formal candidate。
DLA只读诊断和路由，不冒充已修改/复现修好。截图是实际症状；实际CSS计算颜色及隔离回归由DIB验证，不把缺显式text-fill直接作为完整根因证明。

DIB本轮最小边界：
1. 优先只改src/main/resources/style.css中的OLED资源框局部文字颜色，必要时InspectorPane.java给标题/状态/帧数加专用样式类。禁止全局.label改色，不影响左侧黑底OLED、白字草稿徽标、蓝色主按钮、其他页面。验证选中/未选中、可用/禁用、默认/SINGLE/MULTI各资源行，正常文字对比度可读。
2. 不改日志文案或删除中文；先修正新启动配方：当前PowerShell会话使用UTF-8控制台代码页及Console.InputEncoding/OutputEncoding，保留java -Dfile.encoding=UTF-8。$OutputEncoding单独设置不代表控制台解码已统一。覆盖stdout/stderr（含JUL JavaFX警告）和文件日志，以真实中文样本验证，不只ASCII“PASS”。不要改系统全局UTF-8/注册表/用户profile。
3. logback.xml不在当前allowed_paths；当前文件样本正常，不授权本轮修改。如确有证据必须修改生产日志配置或App/Main，报告DLA，不绕过allowed_paths。
4. 允许现有src/test/java/com/example/ahakey/displayconfig下最小隔离CSS/日志编码验证，不新增依赖。日志验证可用独立样本/现成依赖，不启动App/Main/StudioController真实服务，不安装Hook或设备操作。修复前后具体结果留证；仅搜索CSS不当实际JavaFX渲染通过。
5. 用独立的新修复报告、检查证据执行preview-fix-submit，回DLA轻量actual review，再新preview-open/隔离构建。不得直接改旧JAR、旧快照/回执/历史报告。启动命令必须ASCII标点、分行代码块，不再混入中文分号。可以准备新配方记录，不自动执行产品启动。

## 不变与未测

不碰BleManager/协议/事务/连接代次/上传/设备身份/CP1/按键/侧拨/语音/Hook功能；不改固件，不扩CP1.5，不Git写、杀进程、设备写入、烧录或发布。Owner的“先改两个点”不是全产品范围放开。
本次Owner Preview为FAIL（可读性阻断），不填写formal owner_uat fail/pass。其他A01-A11未执行范围继续保留；不要求Owner这会继续测试。
