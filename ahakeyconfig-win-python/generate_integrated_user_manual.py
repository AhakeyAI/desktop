from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile


OUT_PATH = Path.cwd() / "VibecodingKeyboard_Integrated_User_Manual_V1.3.0.docx"


MANUAL = [
    ("title", "Vibecoding Keyboard 使用说明书"),
    ("subtitle", "整合版 V1.3.0 | Windows / macOS 上位机、语音输入、按键配置、宏定义与动画上传"),
    ("normal", "更新时间：2026-04-11"),
    ("normal", "适用对象：首次使用 Vibecoding Keyboard 的用户、测试同事、售后同事，以及需要对照功能验收的产品和研发同事。"),
    ("heading1", "文档结构安排说明"),
    ("normal", "本版说明书不是把旧文档和实操指南简单拼接，而是按真实用户路径重新组织：先理解设备和安装，再启动语音，再连接设备配置按键，最后进入快捷键、宏定义和动画上传等进阶配置。"),
    ("normal", "这样安排的原因是：语音输入和设备键位配置在软件里都出现，但它们不是同一条连接链路。语音输入依赖本地语音服务；按键配置写入设备则需要上位机通过连接程序和设备通信。先把这个关系讲清楚，可以减少“蓝牙已连接但提示请先连接设备”这类误解。"),
    ("normal", "本版同时保留原说明书中的 Windows / macOS 使用路径，并补充当前新版 Windows 端已经加入的首次使用引导、语音状态显示、语音悬浮窗、AhaType 问号说明、提示音开关、Mode0 默认预设显示等内容。"),
    ("heading1", "目录"),
    ("normal", "1. 免责声明与版权说明"),
    ("normal", "2. 产品与设备概览"),
    ("normal", "3. 开箱与硬件基础操作"),
    ("normal", "4. 软件安装与首次启动"),
    ("normal", "5. Windows 上位机使用流程"),
    ("normal", "6. 语音输入与 AhaType"),
    ("normal", "7. 模式配置与 Mode0 默认预设"),
    ("normal", "8. 快捷键设置实操"),
    ("normal", "9. 宏定义设置实操"),
    ("normal", "10. 图片与 GIF 动画上传"),
    ("normal", "11. macOS 上位机使用流程"),
    ("normal", "12. 常见问题与排查"),
    ("normal", "13. 版本修订记录"),

    ("heading1", "1. 免责声明与版权说明"),
    ("normal", "本文档提供有关南京市锦心湾科技有限责任公司相关产品、方案及技术资料的信息。除非另有书面约定，本文档内容不构成任何形式的明示或暗示保证，也不视为授予任何知识产权许可或其他权利。"),
    ("normal", "本文档所载文字、图片、结构设计、技术方案、软件程序及其他相关内容，其著作权、专利权、商标权、商业秘密及其他合法权益均归南京市锦心湾科技有限责任公司所有，并受中华人民共和国相关法律法规保护。未经南京市锦心湾科技有限责任公司事先书面授权，任何单位或个人不得以任何方式对本文档全部或部分内容进行复制、转载、引用、修改、传播、披露、反向工程、出售或用于其他商业用途。"),
    ("normal", "本文档涉及的产品功能、技术参数、接口定义、应用场景及实施方案等内容，可能因产品迭代、版本升级或业务调整而发生变更。南京市锦心湾科技有限责任公司保留在不另行通知的情况下对本文档内容进行补充、修订、更新或撤回的权利。"),
    ("normal", "在订购、部署或使用相关产品与服务前，请与南京市锦心湾科技有限责任公司联系，以获取最新版本的技术说明、产品资料及商务信息。"),
    ("normal", "南京市锦心湾科技有限责任公司保留所有权利。"),
    ("tip", "当前 Windows 上位机右上角也会展示版权声明：Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved. 这属于界面版权声明展示，不是授权校验或防破解机制。"),

    ("heading1", "2. 产品与设备概览"),
    ("normal", "Vibecoding Keyboard 是一款带屏幕显示、模式切换、按键配置和语音输入能力的设备。用户可以通过上位机启动语音输入，也可以连接设备后为按键配置快捷键、宏定义和动画显示内容。"),
    ("heading2", "2.1 设备按键组成"),
    ("normal", "设备一共有 6 个输入控件：1 个电源键、4 个功能按键、1 个拨杆。"),
    ("normal", "电源键：用于开机、关机和切换模式。"),
    ("normal", "4 个功能按键：可在不同模式下配置为预设功能、快捷键或宏定义。"),
    ("normal", "拨杆：用于设备侧扩展交互，具体功能以当前固件和配置为准。"),
    ("heading2", "2.2 模式概念"),
    ("normal", "键盘预设有 3 个模式：Mode0、Mode1、Mode2。每个模式都有独立的 4 个功能按键配置，也可以配置独立的屏幕图片或 GIF 动画。"),
    ("normal", "Mode0 当前作为默认 Vibecoding 功能模式。Windows 新版上位机在 Mode0 没有真实自定义值时，会在界面上直接显示默认预设：Key1 为 Cap，Key2 为 YES，Key3 为 NO，Key4 为 Enter。"),
    ("normal", "这个预设显示只是界面层默认值，不会在加载界面时静默写入设备或本地配置。如果用户自己修改过某个键位，则优先显示用户真实配置。"),

    ("heading1", "3. 开箱与硬件基础操作"),
    ("heading2", "3.1 开机"),
    ("normal", "短按电源按键，设备屏幕正常亮起即表示开机成功。如果屏幕没有亮起，设备可能需要充电。"),
    ("heading2", "3.2 关机"),
    ("normal", "长按电源按键，直到指示灯变为红色后快速熄灭，即表示设备关机。"),
    ("heading2", "3.3 模式切换"),
    ("normal", "短按电源按键即可循环切换 Mode0、Mode1、Mode2。切换后屏幕内容和按键功能会按照当前模式的配置生效。"),
    ("heading2", "3.4 蓝牙配对"),
    ("normal", "短按设备右下角白色按键，让设备进入配对模式。在电脑蓝牙设置中找到 vibe code 或 vibe code xxxx，完成连接。蓝牙连接成功后，键盘通常会显示白色灯光。"),
    ("tip", "蓝牙连接成功后，设备可以作为蓝牙设备使用；但如果要在上位机里点击“应用按键到设备”或“保存到设备”，还需要上位机顶部连接栏连接到设备通信服务。"),

    ("heading1", "4. 软件安装与首次启动"),
    ("heading2", "4.1 Windows 安装"),
    ("normal", "运行 VibecodingKeyboard_Setup.exe。由于安装包包含本地语音模型，打开或安装过程可能较慢，请耐心等待。"),
    ("normal", "建议不要安装到 C 盘 Program Files 或 Program Files (x86) 目录，避免后续写入配置、日志或模型文件时受到系统权限限制。"),
    ("normal", "安装过程中如出现绿色或蓝色安装按钮，请按安装向导提示完成安装。完成后可以按默认勾选启动上位机、蓝牙连接程序或 Hook 安装程序。"),
    ("heading2", "4.2 首次使用引导"),
    ("normal", "Windows 新版上位机首次打开主窗口后，会弹出“欢迎使用 Vibecoding Keyboard”的轻量引导弹窗。它会提示用户优先从“启动语音”和“连接设备和配置按键”两个入口开始。"),
    ("normal", "这个引导弹窗只会自动出现一次，用户点击“我知道了”后会记录本地状态。后续如果需要重新查看，可以从菜单中的“查看功能引导”打开。"),
    ("heading2", "4.3 顶部连接栏结构"),
    ("normal", "主窗口顶部连接栏从左到右主要包括：IP、Port、连接、启动语音输入或停止语音输入、语音状态灯、语音状态文字、提示音开关、启动 AhaType、AhaType 问号说明。"),
    ("normal", "连接按钮用于连接设备配置链路。启动语音输入按钮用于启动本地语音服务。两者不是同一个功能入口。"),

    ("heading1", "5. Windows 上位机使用流程"),
    ("heading2", "5.1 启动上位机"),
    ("normal", "安装完成后，打开桌面快捷方式 Vibecoding Keyboard.exe 或安装目录中的 KeyboardConfig.exe。"),
    ("normal", "如果只是体验语音输入，可以先点击“启动语音输入”。如果要写入按键、宏或动画配置，需要先确保蓝牙连接程序和设备通信链路正常，再点击顶部“连接”。"),
    ("heading2", "5.2 连接设备配置链路"),
    ("normal", "默认 IP 通常为 127.0.0.1，默认 Port 通常为 9000。确认蓝牙连接程序已运行后，在上位机顶部点击“连接”。"),
    ("normal", "连接成功后，设备信息栏会更新状态，此时可以在模式配置页执行“应用按键到设备”“上传到设备”“保存到设备”等操作。"),
    ("tip", "如果点击“应用按键到设备”时提示“请先连接设备”，说明上位机配置链路还没有连上。即使蓝牙已经连接、语音输入也能用，仍然需要在上位机顶部点击“连接”完成配置链路连接。"),
    ("heading2", "5.3 保存配置"),
    ("normal", "如果只想快速测试当前按键，可以在“按键映射”区域点击“应用按键到设备”。"),
    ("normal", "如果既修改了按键，又修改了动画，建议最后使用菜单“文件 -> 保存到设备”，做一次完整保存。"),

    ("heading1", "6. 语音输入与 AhaType"),
    ("heading2", "6.1 启动语音输入"),
    ("normal", "点击顶部“启动语音输入”，上位机会启动本地语音服务。启动过程中右侧状态灯和状态文字会显示当前进度，例如语音启动中、服务已启动等待客户端连接、语音已就绪等。"),
    ("normal", "当状态显示为“语音已就绪”后，将光标放到需要输入文字的位置，按住键盘语音键开始录音，说完后松开即可开始识别和输入。"),
    ("normal", "点击“停止语音输入”可以关闭语音服务。关闭软件时，语音输入也会一起关闭。"),
    ("heading2", "6.2 语音状态显示"),
    ("normal", "顶部语音状态灯用于常驻显示当前总体状态：灰色空心圆表示语音未启动；橙色旋转表示启动中、关闭中或处理中；红色实心圆表示录音中或异常；绿色实心圆表示语音已就绪。"),
    ("normal", "状态文字会显示语音未启动、语音启动中、录音中、处理中、语音已就绪、语音关闭中、语音异常等信息。实际运行时也可能显示更细的业务提示，如模型加载中、服务已启动等待客户端连接、本地识别中、AhaType 整理中、准备粘贴等。"),
    ("heading2", "6.3 语音悬浮窗"),
    ("normal", "语音悬浮窗用于在录音、识别、准备粘贴、异常等关键阶段提供即时反馈。它不是替代顶部状态栏，而是补充状态反馈。"),
    ("normal", "悬浮窗通常显示在屏幕中下方，不抢焦点，不阻挡用户继续输入。成功或就绪类状态会短暂显示后自动隐藏，录音中和处理中通常会持续显示到下一阶段，错误状态会显示更久一点。"),
    ("heading2", "6.4 提示音开关"),
    ("normal", "顶部连接栏提供“提示音：开 / 提示音：关”按钮，用于控制开始录音和结束录音时是否播放提示音。"),
    ("normal", "默认值为开启。点击一次即可在开和关之间切换，按钮文字会立即更新。设置会保存到本地，下次打开应用时沿用上一次选择。"),
    ("heading2", "6.5 AhaType"),
    ("normal", "AhaType 会把语音识别结果再做一次整理和润色，适合用于口语转书面语、补全标点，或让输入内容更适合直接发送和记录。"),
    ("normal", "使用前需要先登录，并且云端服务可用。点击用户信息页可以注册或登录，登录后可以兑换或充值 AhaType 兑换码，并查看每日、每周、每月 Token 使用额度。"),
    ("normal", "顶部“启动 AhaType”按钮右侧有问号说明按钮，点击后可以查看轻量说明，不会跳转页面或打开浏览器。"),

    ("heading1", "7. 模式配置与 Mode0 默认预设"),
    ("heading2", "7.1 模式配置页结构"),
    ("normal", "进入“模式配置”页后，顶部可以选择 Mode0、Mode1、Mode2。页面左侧为按键映射，右侧为动画管理。"),
    ("normal", "按键映射区域包含 4 个可视化按键、按键描述、按键类型、快捷键或宏的具体编辑面板，以及“应用按键到设备”按钮。"),
    ("normal", "动画管理区域用于添加图片、添加 GIF、删除、清空、调整 FPS、播放预览，以及上传到设备。"),
    ("heading2", "7.2 Mode0 默认预设"),
    ("normal", "Mode0 在没有真实自定义值时，会显示默认预设：Key1 -> F18，Key2 -> YES，Key3 -> NO，Key4 -> Enter。"),
    ("normal", "这只是显示层默认值，不会静默写回设备或本地配置。如果用户为某个键设置了描述、快捷键或宏，界面会优先显示用户真实配置。"),
    ("heading2", "7.3 问号说明按钮"),
    ("normal", "按键映射标题右侧有问号说明按钮，用于说明这里可以给当前模式下的每个按键分配功能，适合设置常用快捷键、组合键、文本输入或不同模式下的专用布局。"),
    ("normal", "动画管理标题右侧也有问号说明按钮，用于说明这里可以上传图片或 GIF，生成设备显示用的动画帧，适合自定义开机动画、模式显示效果或不同模式的视觉反馈。"),

    ("heading1", "8. 快捷键设置实操"),
    ("heading2", "8.1 什么时候用快捷键"),
    ("normal", "快捷键适合一次性组合按键，例如 Ctrl+C、Ctrl+V、Ctrl+Shift+Esc、Win+E、Alt+Tab。"),
    ("normal", "如果只是一个简单组合键，优先使用“快捷键”类型；如果需要分步骤按下、延时、释放，则使用“宏”。"),
    ("heading2", "8.2 示例：把 Key1 设置为 Ctrl+C 复制"),
    ("normal", "1. 进入“模式配置”页，选择要配置的模式，例如 Mode1。"),
    ("normal", "2. 在左侧 4 键示意图里点击 Key1。"),
    ("normal", "3. 在“按键描述”里输入便于识别的名字，例如 CTRL_C_COPY。按键描述会显示在键盘屏幕上，建议使用英文、数字或下划线，最多 20 个 ASCII 字符。"),
    ("normal", "4. 在“按键类型”中选择“快捷键”。"),
    ("normal", "5. 在键码下拉框中选择 Left Ctrl，点击“添加”。"),
    ("normal", "6. 再选择字母 C，点击“添加”。"),
    ("normal", "7. 列表里应能看到 Left Ctrl 和 C 两个条目。快捷键标签通常会显示为 Left Ctrl + C。"),
    ("normal", "8. 如果加错了，先在列表里选中错误条目，再点击“删除”。"),
    ("normal", "9. 确认无误后，如果只是快速测试，点击“应用按键到设备”。如果要整套配置保存，最后再使用“文件 -> 保存到设备”。"),
    ("heading2", "8.3 更多快捷键例子"),
    ("normal", "Ctrl + V：依次添加 Left Ctrl、V。"),
    ("normal", "Ctrl + Shift + Esc：依次添加 Left Ctrl、Left Shift、Escape。"),
    ("normal", "Win + E：依次添加 Left Win、E。"),
    ("normal", "Alt + Tab：依次添加 Left Alt、Tab。"),
    ("tip", "快捷键组合的习惯是修饰键放前面，普通键放后面。例如 Ctrl+C 是先添加 Ctrl，再添加 C。"),
    ("heading2", "8.4 快捷键测试"),
    ("normal", "连接设备并应用或保存配置后，打开一个可测试程序，例如记事本、资源管理器或浏览器。"),
    ("normal", "如果配置的是 Ctrl+C，先手动选中一段文字，再按设备上的对应按键，看是否成功复制。"),
    ("normal", "如果没有反应，优先检查是否已经在上位机顶部点击“连接”，是否已经点击“应用按键到设备”或“保存到设备”，以及目标键是否真的添加到了键码列表。"),

    ("heading1", "9. 宏定义设置实操"),
    ("heading2", "9.1 宏和快捷键的区别"),
    ("normal", "快捷键适合一次性组合按键；宏适合分步骤执行动作。"),
    ("normal", "例如 Ctrl+C 可以用快捷键实现，也可以用宏实现。宏实现时一般会先按下 Ctrl，再按下 C，延时一小段时间，再释放 C，再释放 Ctrl，最后释放全部按键。"),
    ("normal", "当前宏步骤支持四类核心动作：按下按键、释放按键、释放全部按键、延时。延时参数单位约为 value × 3ms，例如 30 约等于 90ms。"),
    ("heading2", "9.2 示例：用宏实现 Ctrl+C 复制"),
    ("normal", "推荐宏步骤如下："),
    ("normal", "1. 按下按键 -> Left Ctrl"),
    ("normal", "2. 按下按键 -> C"),
    ("normal", "3. 延时 -> 30，约 90ms"),
    ("normal", "4. 释放按键 -> C"),
    ("normal", "5. 释放按键 -> Left Ctrl"),
    ("normal", "6. 释放全部按键"),
    ("normal", "实际操作流程："),
    ("normal", "1. 选中一个按键，例如 Key2。"),
    ("normal", "2. 在“按键描述”中输入 MACRO_COPY。"),
    ("normal", "3. 在“按键类型”中选择“宏”。"),
    ("normal", "4. 动作选择“按下按键”，参数选择 Left Ctrl，点击“添加步骤”。"),
    ("normal", "5. 再次选择“按下按键”，参数选择 C，点击“添加步骤”。"),
    ("normal", "6. 动作切换为“延时”，参数输入 30，点击“添加步骤”。"),
    ("normal", "7. 动作切换为“释放按键”，参数选择 C，点击“添加步骤”。"),
    ("normal", "8. 再添加一步“释放按键 -> Left Ctrl”。"),
    ("normal", "9. 最后添加一步“释放全部按键”。"),
    ("normal", "10. 完成后点击“应用按键到设备”或“保存到设备”。"),
    ("tip", "建议宏的最后加“释放全部按键”，这样即使前面某一步释放失败，也能减少修饰键被卡住的概率。"),
    ("heading2", "9.3 示例：用宏实现 Win+R 打开运行窗口"),
    ("normal", "推荐宏步骤如下："),
    ("normal", "1. 按下按键 -> Left Win"),
    ("normal", "2. 按下按键 -> R"),
    ("normal", "3. 延时 -> 20，约 60ms"),
    ("normal", "4. 释放按键 -> R"),
    ("normal", "5. 释放按键 -> Left Win"),
    ("normal", "6. 释放全部按键"),
    ("heading2", "9.4 宏定义常见问题"),
    ("normal", "如果宏执行太快，系统可能来不及响应，可以适当增加延时，例如 20、30、50。"),
    ("normal", "如果宏里需要组合键，通常推荐先按下修饰键，再按下目标键，延时后先释放目标键，再释放修饰键。"),
    ("normal", "如果动作顺序写反，可能导致效果和预期不一致。若步骤加错，可以在宏步骤列表里选中错误步骤，再点击“删除步骤”。"),

    ("heading1", "10. 图片与 GIF 动画上传"),
    ("heading2", "10.1 动画管理是做什么的"),
    ("normal", "动画管理用于配置当前模式的屏幕显示内容。可以给 Mode0、Mode1、Mode2 分别配置不同的图片或 GIF 动画。"),
    ("normal", "当前设备屏幕目标尺寸为 160 × 80。软件会自动把导入图片缩放并居中到这个尺寸。原图不一定必须提前裁成 160 × 80，但提前按比例处理通常效果更可控。"),
    ("heading2", "10.2 上传单张或多张图片"),
    ("normal", "1. 进入“模式配置”页，切换到要编辑的模式。"),
    ("normal", "2. 在右侧“动画管理”中点击“添加图片”。"),
    ("normal", "3. 选择一张或多张图片，支持 png、jpg、jpeg、bmp。"),
    ("normal", "4. 导入后图片会出现在帧列表里。点击某一帧，可以在下方预览区看到处理后的效果。"),
    ("normal", "5. 如果只有单张图片，也可以上传，它会作为当前模式的静态显示画面。"),
    ("heading2", "10.3 上传 GIF"),
    ("normal", "1. 点击“添加 GIF”。"),
    ("normal", "2. 选择一个 GIF 文件。"),
    ("normal", "3. 软件会自动把 GIF 拆成多帧，并把每一帧加入当前模式的帧列表。"),
    ("normal", "4. 导入完成后，帧列表数量会增加，右下角会显示总帧数。"),
    ("normal", "5. 可以点击“播放预览”先看动画效果。"),
    ("normal", "6. 如果速度不合适，可以调整 FPS。FPS 越高，动画播放越快。当前最高支持 30 FPS。"),
    ("normal", "7. 确认无误后，点击“上传到设备”。"),
    ("heading2", "10.4 整理帧列表"),
    ("normal", "删除：选中某一帧，点击“删除”。"),
    ("normal", "清空：点击“清空”，删除当前模式下所有帧。"),
    ("normal", "调整顺序：帧列表支持拖拽排序。拖动后的顺序就是最终动画播放顺序。"),
    ("normal", "FPS：可设置 1 到 30。一般建议从 8 到 12 开始试，既清楚也比较稳定。"),
    ("heading2", "10.5 动图上传限制"),
    ("normal", "设备总帧容量有限，当前总上限约为 74 帧，并且是 3 个模式共享总量。"),
    ("normal", "如果某个模式的 GIF 帧太多，可能会挤占其他模式的动画空间。上传时软件会检查空间，如果有冲突或超限，会给出提示。"),
    ("normal", "如果 GIF 很长，建议先在外部工具里裁掉不必要的帧，再导入。实操上更推荐短 GIF 加合适 FPS，不建议直接上传很长的大动画。"),
    ("heading2", "10.6 推荐收尾流程"),
    ("normal", "如果既改了按键，又改了动画，最稳妥的流程是：先分别确认按键和动画都能正常工作，最后再执行一次“文件 -> 保存到设备”。"),

    ("heading1", "11. macOS 上位机使用流程"),
    ("heading2", "11.1 macOS 安装"),
    ("normal", "双击 VibeCodeKeyboard-macos-0.1.1.dmg。由于包含本地模型，打开可能较慢。"),
    ("normal", "将键盘软件图标拖拽到 Applications 中，然后前往应用程序打开软件。"),
    ("heading2", "11.2 Hook 和权限"),
    ("normal", "首次打开时，如果提示尚未安装 Hook，点击 YES 去安装。安装界面中按提示点击安装按钮，安装完成后关闭页面即可。"),
    ("normal", "启动语音输入时，系统可能会请求麦克风权限，请允许。"),
    ("normal", "macOS 还需要手动开启输入监控和辅助功能权限。按提示打开输入监控设置，点击加号，找到 Vibecoding Keyboard 并添加。辅助功能权限也按同样方式添加。"),
    ("normal", "完成权限设置后，回到软件点击“已开启权限，下一步”。软件可能会自动关闭并重启。如果没有重启，可以回到应用程序手动重新打开。"),
    ("heading2", "11.3 macOS 启动语音"),
    ("normal", "重新打开软件后点击“启动语音输入”，等待状态提示语音已就绪。将鼠标光标定位到输入位置，长按键盘语音键，说话即可输入。"),
    ("normal", "点击“停止语音输入”即可关闭语音模型。关闭软件时，语音输入也会关闭。"),
    ("heading2", "11.4 macOS 键位和动画配置"),
    ("normal", "macOS 端的模式配置思路与 Windows 保持一致：先连接设备，再选择 Mode0、Mode1 或 Mode2，然后编辑按键映射或动画管理。"),
    ("normal", "快捷键、宏定义、图片和 GIF 上传的配置原则与本说明书前文一致。若界面位置略有差异，以 macOS 实际界面为准。"),

    ("heading1", "12. 常见问题与排查"),
    ("heading2", "12.1 蓝牙连接了，为什么应用按键还提示请先连接设备"),
    ("normal", "蓝牙连接表示设备已经作为蓝牙设备连到电脑，可以用于部分输入或语音相关体验。"),
    ("normal", "但“应用按键到设备”“保存到设备”“上传到设备”需要上位机通过设备通信服务连接到设备。请确认蓝牙连接程序已启动，然后在上位机顶部点击“连接”。"),
    ("heading2", "12.2 启动语音后没有反应"),
    ("normal", "先看顶部状态文字是否显示“语音已就绪”。如果一直停留在启动中，可能是本地语音服务或模型加载较慢，也可能是服务启动失败。"),
    ("normal", "如果状态显示异常，请关闭后重新启动语音输入。Windows 端也可以查看 Capswriter 日志，macOS 端优先检查麦克风、输入监控和辅助功能权限。"),
    ("heading2", "12.3 Ctrl+C 没有复制"),
    ("normal", "先确认目标程序中已经选中文本。再确认上位机已连接设备，且已经点击“应用按键到设备”或“保存到设备”。最后检查快捷键列表中是否同时包含 Left Ctrl 和 C。"),
    ("heading2", "12.4 宏执行不稳定"),
    ("normal", "可以适当增加延时，确认按下和释放顺序是否正确，并在最后加入“释放全部按键”。"),
    ("heading2", "12.5 GIF 上传后效果不对"),
    ("normal", "检查帧顺序是否正确，FPS 是否过快或过慢，GIF 是否太长导致超出空间，原图比例是否和 160 × 80 相差过大。"),
    ("heading2", "12.6 AhaType 无法开启"),
    ("normal", "AhaType 使用前需要登录，并且云端服务可用。如果没有登录，先进入“用户信息”页完成注册或登录。"),
    ("heading2", "12.7 遇到报错怎么办"),
    ("normal", "如果遇到问题，请联系售后或客服。反馈时建议提供：操作系统、软件版本、设备连接状态、问题复现步骤、设备信息栏或通信日志中的错误内容。"),

    ("heading1", "13. 版本修订记录"),
    ("normal", "V1.0.1 | 2026-03-01 | 锦心湾技术团队 | 基础内容"),
    ("normal", "V1.0.2 | 2026-03-25 | 锦心湾技术团队 | 新增功能更新"),
    ("normal", "V1.2.0 | 2026-04-11 | 锦心湾技术团队 | 原使用文档版本"),
    ("normal", "V1.3.0 | 2026-04-11 | OpenAI Codex 辅助整理 | 整合原说明书与快捷键、宏定义、GIF 上传实操指南，补充新版 Windows 功能说明，重排说明书结构。"),
    ("heading1", "附录：快速操作卡片"),
    ("normal", "设置复制快捷键：模式配置 -> 选择模式 -> 选择 Key -> 描述填 CTRL_C_COPY -> 按键类型选快捷键 -> 添加 Left Ctrl -> 添加 C -> 应用按键到设备。"),
    ("normal", "设置宏复制键：模式配置 -> 选择 Key -> 描述填 MACRO_COPY -> 按键类型选宏 -> 按下 Left Ctrl -> 按下 C -> 延时 30 -> 释放 C -> 释放 Left Ctrl -> 释放全部按键 -> 应用按键到设备。"),
    ("normal", "上传 GIF：模式配置 -> 选择模式 -> 动画管理 -> 添加 GIF -> 调整 FPS -> 播放预览 -> 上传到设备 -> 文件 -> 保存到设备。"),
    ("normal", "启动语音：打开上位机 -> 启动语音输入 -> 等待语音已就绪 -> 将光标放到输入位置 -> 长按键盘语音键说话 -> 松开识别输入。"),
]


def paragraph(text: str, style: str = "Normal", bold: bool = False, size: int | None = None, color: str | None = None, spacing_after: int = 120) -> str:
    text = escape(text)
    run_props = ""
    if bold:
        run_props += "<w:b/>"
    if size is not None:
        run_props += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    if color:
        run_props += f'<w:color w:val="{color}"/>'
    p_props = f'<w:pStyle w:val="{style}"/><w:spacing w:after="{spacing_after}"/>'
    return f'<w:p><w:pPr>{p_props}</w:pPr><w:r><w:rPr>{run_props}</w:rPr><w:t xml:space="preserve">{text}</w:t></w:r></w:p>'


body_xml = []
for kind, text in MANUAL:
    if kind == "title":
        body_xml.append(paragraph(text, style="Title", bold=True, size=36, spacing_after=220))
    elif kind == "subtitle":
        body_xml.append(paragraph(text, style="Subtitle", size=22, color="666666", spacing_after=220))
    elif kind == "heading1":
        body_xml.append(paragraph(text, style="Heading1", bold=True, size=28, color="1F4E79", spacing_after=140))
    elif kind == "heading2":
        body_xml.append(paragraph(text, style="Heading2", bold=True, size=24, color="404040", spacing_after=120))
    elif kind == "tip":
        body_xml.append(paragraph("提示：" + text, style="Tip", size=21, color="1F4E79", spacing_after=140))
    else:
        body_xml.append(paragraph(text, style="Normal", size=21, spacing_after=90))


section_xml = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'

document_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" xmlns:wne="http://schemas.microsoft.com/office/2006/wordml" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" mc:Ignorable="w14 w15 wp14"><w:body>{''.join(body_xml)}{section_xml}</w:body></w:document>'''

styles_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:eastAsia="Microsoft YaHei" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:rPrDefault>
    <w:pPrDefault><w:pPr><w:spacing w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:eastAsia="Microsoft YaHei"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:qFormat/><w:rPr><w:b/><w:rFonts w:eastAsia="Microsoft YaHei"/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:rPr><w:rFonts w:eastAsia="Microsoft YaHei"/><w:color w:val="666666"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:rFonts w:eastAsia="Microsoft YaHei"/><w:color w:val="1F4E79"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:rFonts w:eastAsia="Microsoft YaHei"/><w:color w:val="404040"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Tip"><w:name w:val="Tip"/><w:basedOn w:val="Normal"/><w:rPr><w:rFonts w:eastAsia="Microsoft YaHei"/><w:color w:val="1F4E79"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:style>
</w:styles>'''

content_types_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>'''

rels_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>'''

document_rels_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'''

now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
core_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Vibecoding Keyboard 使用说明书 整合版 V1.3.0</dc:title>
  <dc:creator>OpenAI Codex</dc:creator>
  <cp:lastModifiedBy>OpenAI Codex</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>
</cp:coreProperties>'''

app_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Microsoft Office Word</Application>
</Properties>'''

with ZipFile(OUT_PATH, "w", ZIP_DEFLATED) as zf:
    zf.writestr("[Content_Types].xml", content_types_xml)
    zf.writestr("_rels/.rels", rels_xml)
    zf.writestr("docProps/core.xml", core_xml)
    zf.writestr("docProps/app.xml", app_xml)
    zf.writestr("word/document.xml", document_xml)
    zf.writestr("word/styles.xml", styles_xml)
    zf.writestr("word/_rels/document.xml.rels", document_rels_xml)

print(OUT_PATH)
print(OUT_PATH.stat().st_size)
