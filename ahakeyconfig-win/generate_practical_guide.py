from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile


OUT_PATH = Path.cwd() / "VibecodingKeyboard_Practical_Guide.docx"


PARAGRAPHS = [
    ("title", "Vibecoding Keyboard 实操指南"),
    ("subtitle", "适用范围：Windows 配置工具中设置快捷键、设置宏定义、上传图片 / GIF 动图到设备"),
    ("normal", "文档目的：这份指南按当前 Windows 配置工具的实际界面编写，重点回答“具体怎么点、怎么配、怎么测试”。看完后，你应该可以独立完成 Ctrl+C 快捷键设置、宏定义设置，以及动图上传。"),
    ("heading1", "一、开始前先确认的事项"),
    ("normal", "1. 打开配置工具 KeyboardConfig.exe。"),
    ("normal", "2. 如果要把配置真正写入设备，请先在顶部点击“连接”，连接成功后再继续。"),
    ("normal", "3. 进入“模式配置”页。这个页面就是日常配置按键和动画的主工作区。"),
    ("normal", "4. 顶部可以切换 Mode 0 / Mode 1 / Mode 2。每个 Mode 都有自己独立的 4 个按键和动画。"),
    ("normal", "5. 中间左侧是 4 个按键的可视化区域，右侧是当前选中按键的编辑区；更右边是“动画管理”。"),
    ("tip", "实操建议：先确定你要改的是哪个模式，再点击要编辑的 Key 1 / Key 2 / Key 3 / Key 4。后面的所有设置，都是对当前模式下当前选中的按键生效。"),
    ("heading1", "二、怎么把某个按键设置成快捷键"),
    ("heading2", "场景示例：把一个按键设置为 Ctrl + C 复制"),
    ("normal", "操作步骤："),
    ("normal", "1. 进入“模式配置”页，先选择要配置的模式，例如 Mode 0。"),
    ("normal", "2. 在左侧 4 键示意图里点击你要设置的那个键，例如 Key 1。"),
    ("normal", "3. 在“按键描述”里输入一个便于识别的名字，例如 CTRL_C_COPY。"),
    ("normal", "4. 注意：按键描述会显示在键盘屏幕上，当前限制是最多 20 个 ASCII 字符。最稳妥的写法是英文字母、数字、下划线。不要依赖中文、emoji 或很长的文本。"),
    ("normal", "5. 在“按键类型”中选择“快捷键”。"),
    ("normal", "6. 在“键码列表”区域的下拉框中，先选择 Left Ctrl，再点击“添加”。"),
    ("normal", "7. 再在下拉框中选择字母 C，再点击“添加”。"),
    ("normal", "8. 这时列表里应该能看到两个条目：Left Ctrl 和 C。快捷键标签通常会显示成 Left Ctrl + C。"),
    ("normal", "9. 如果加错了，先在列表中点中错误项，再点击“删除”。"),
    ("normal", '10. 如果你只是想快速测试这个按键，可点击“应用按键到设备”。'),
    ("normal", '11. 如果你希望和动画一起完整保存，建议最后使用菜单“文件 -> 保存到设备”。'),
    ("tip", "快捷键组合的习惯：修饰键放前面，普通键放后面。例如 Ctrl+C、Ctrl+V、Ctrl+Shift+Esc，都是先加 Ctrl / Shift，再加 C / V / Esc。"),
    ("heading2", "更多快捷键例子"),
    ("normal", "Ctrl + V：依次添加 Left Ctrl、V。"),
    ("normal", "Ctrl + Shift + Esc：依次添加 Left Ctrl、Left Shift、Escape。"),
    ("normal", "Win + E：依次添加 Left Win、E。"),
    ("normal", "Alt + Tab：依次添加 Left Alt、Tab。"),
    ("heading2", "快捷键配置完成后怎么验证"),
    ("normal", "1. 连接设备后点击“应用按键到设备”或“保存到设备”。"),
    ("normal", "2. 打开一个可以测试的程序，例如记事本、资源管理器或浏览器。"),
    ("normal", "3. 按下设备上的对应键。"),
    ("normal", "4. 例如如果你配的是 Ctrl+C，就先手动选中一段文字，再按设备键，看是否成功复制。"),
    ("normal", "5. 如果没有反应，先检查三件事：是否真的连接到设备、是否已经点击应用/保存、是否把目标键加进列表了。"),
    ("heading1", "三、怎么把某个按键设置成宏定义"),
    ("normal", "宏和快捷键的区别："),
    ("normal", "1. 快捷键适合“一次性组合按键”，例如 Ctrl+C。"),
    ("normal", "2. 宏适合“分步骤执行动作”，例如先按下 Ctrl，再按下 C，延迟一小会，再释放 C，再释放 Ctrl。"),
    ("normal", "3. 当前宏步骤支持 4 类核心动作：按下按键、释放按键、释放全部按键、延时。"),
    ("normal", "4. 其中“延时”的参数单位是 value × 3ms。例如参数 30，大约就是 90ms。"),
    ("heading2", "场景示例 1：用宏实现 Ctrl + C 复制"),
    ("normal", "推荐宏步骤如下："),
    ("normal", "1. 按下按键 -> Left Ctrl"),
    ("normal", "2. 按下按键 -> C"),
    ("normal", "3. 延时 -> 30（约 90ms）"),
    ("normal", "4. 释放按键 -> C"),
    ("normal", "5. 释放按键 -> Left Ctrl"),
    ("normal", "6. 释放全部按键"),
    ("normal", "对应的实际操作："),
    ("normal", "1. 选中一个按键，例如 Key 2。"),
    ("normal", "2. 在“按键描述”中输入一个名字，例如 MACRO_COPY。"),
    ("normal", "3. 在“按键类型”中选择“宏”。"),
    ("normal", "4. 在“动作”下拉框中选择“按下按键”，参数里选择 Left Ctrl，点击“添加步骤”。"),
    ("normal", "5. 再次选择“按下按键”，参数选择 C，点击“添加步骤”。"),
    ("normal", "6. 动作切换为“延时”，参数输入 30，点击“添加步骤”。"),
    ("normal", "7. 动作切换为“释放按键”，参数选择 C，点击“添加步骤”。"),
    ("normal", "8. 再添加一步“释放按键 -> Left Ctrl”。"),
    ("normal", "9. 最后再添加一步“释放全部按键”。"),
    ("normal", "10. 完成后点击“应用按键到设备”或“保存到设备”。"),
    ("tip", "为什么推荐最后加“释放全部按键”：这样即使前面某一步释放失败，也能减少修饰键被卡住的概率。"),
    ("heading2", "场景示例 2：用宏实现 Win + R 打开运行窗口"),
    ("normal", "推荐宏步骤如下："),
    ("normal", "1. 按下按键 -> Left Win"),
    ("normal", "2. 按下按键 -> R"),
    ("normal", "3. 延时 -> 20（约 60ms）"),
    ("normal", "4. 释放按键 -> R"),
    ("normal", "5. 释放按键 -> Left Win"),
    ("normal", "6. 释放全部按键"),
    ("heading2", "宏定义常见问题"),
    ("normal", "1. 如果宏执行太快，系统可能来不及响应，可以适当增加“延时”，例如 20、30、50。"),
    ("normal", "2. 如果宏里需要组合键，通常推荐“先按下修饰键 -> 再按下目标键 -> 延时 -> 先释放目标键 -> 再释放修饰键”。"),
    ("normal", "3. 如果动作顺序写反，可能导致效果和预期不一致。"),
    ("normal", "4. 如果步骤加错了，可以在宏步骤列表里选中错误步骤，再点击“删除步骤”。"),
    ("heading1", "四、怎么上传静态图片或 GIF 动图"),
    ("heading2", "先理解这块界面是做什么的"),
    ("normal", "“动画管理”是针对当前模式的屏幕显示内容。你可以给 Mode 0、Mode 1、Mode 2 分别配置不同的图片或动画。"),
    ("normal", "当前显示屏的目标尺寸是 160 × 80。软件会自动把导入的图片缩放并居中到这个尺寸，所以原图不一定必须自己先裁成 160 × 80，但这么做通常效果会更可控。"),
    ("heading2", "上传单张图片的流程"),
    ("normal", "1. 进入“模式配置”页，并切换到你要编辑的模式，例如 Mode 1。"),
    ("normal", "2. 在右侧“动画管理”区域点击“添加图片”。"),
    ("normal", "3. 选择一张或多张图片，支持 png、jpg、jpeg、bmp。"),
    ("normal", "4. 导入后，这些图片会出现在帧列表里。"),
    ("normal", "5. 点击某一帧，可以在下方预览区看到处理后的效果。"),
    ("normal", "6. 如果只是单张图，也可以上传，它会作为当前模式的静态显示画面。"),
    ("heading2", "上传 GIF 的流程"),
    ("normal", "1. 点击“添加 GIF”。"),
    ("normal", "2. 选择一个 GIF 文件。"),
    ("normal", "3. 软件会自动把 GIF 拆成多帧，并把每一帧加入当前模式的帧列表。"),
    ("normal", "4. 导入完成后，帧列表数量会增加，右下角会显示总帧数。"),
    ("normal", "5. 你可以点“播放预览”先看动画效果。"),
    ("normal", "6. 如果速度不合适，可以调整 FPS。FPS 越高，动画播放越快。"),
    ("normal", "7. 确认无误后，点击“上传到设备”。"),
    ("heading2", "整理帧列表的常用操作"),
    ("normal", "1. 删除：选中某一帧，点击“删除”。"),
    ("normal", "2. 清空：点击“清空”，删除当前模式下所有帧。"),
    ("normal", "3. 调整顺序：帧列表支持拖拽排序。你拖动的顺序，就是最终动画播放顺序。"),
    ("normal", "4. FPS：可设置 1 到 30。一般建议从 8 到 12 开始试，既清楚也比较稳。"),
    ("heading2", "上传动图时要特别注意的限制"),
    ("normal", "1. 设备的总帧容量有限，当前总上限是 74 帧，而且这是 3 个模式共享的总量。"),
    ("normal", "2. 如果某个模式 GIF 帧太多，可能会挤占其他模式的动画空间。"),
    ("normal", "3. 上传时软件会检查空间，如果有冲突或超限，会给出提示。"),
    ("normal", "4. 如果 GIF 很长，建议先在外部工具里裁掉不必要的帧，再导入。"),
    ("normal", "5. 实操上更推荐“短 GIF + 合适 FPS”，不要直接塞一个很长的大动画。"),
    ("heading2", "图片 / GIF 上传完成后怎么保存"),
    ("normal", "有两种常见方式："),
    ("normal", "1. 只处理动画：在“动画管理”里点“上传到设备”。这一步主要针对动画帧。"),
    ("normal", "2. 做整套配置落盘：使用菜单“文件 -> 保存到设备”。这一步会连同按键映射和动画一起保存。"),
    ("tip", "如果你既改了按键，又改了动画，最稳的收尾方式是：先分别确认按键和动画都没问题，最后再执行一次“文件 -> 保存到设备”。"),
    ("heading1", "五、推荐的完整操作流程（最适合新手）"),
    ("normal", "1. 打开配置工具并连接设备。"),
    ("normal", "2. 进入“模式配置”页。"),
    ("normal", "3. 先选中要编辑的模式。"),
    ("normal", "4. 点击对应的按键，先设置按键描述。"),
    ("normal", "5. 如果这个键只是做普通组合键，用“快捷键”。"),
    ("normal", "6. 如果这个键要做分步骤动作，用“宏”。"),
    ("normal", "7. 右侧“动画管理”里再给当前模式添加图片或 GIF。"),
    ("normal", "8. 先用“播放预览”确认动画效果。"),
    ("normal", "9. 先点“应用按键到设备”测试按键逻辑；动画则点“上传到设备”测试显示效果。"),
    ("normal", "10. 全部确认无误后，再用菜单“文件 -> 保存到设备”做最终保存。"),
    ("heading1", "六、最常见的错误排查"),
    ("normal", "问题 1：设备按下去没有反应。"),
    ("normal", "排查：是否已连接设备；是否点了“应用按键到设备”或“保存到设备”；是否正在编辑的是正确的模式和正确的 Key。"),
    ("normal", "问题 2：Ctrl+C 没有复制。"),
    ("normal", "排查：目标程序里是否先选中了文本；快捷键列表里是否同时包含 Left Ctrl 和 C；有没有误删其中一个。"),
    ("normal", "问题 3：宏执行不稳定。"),
    ("normal", "排查：是否需要加延时；是否释放顺序写反；是否忘了最后加“释放全部按键”。"),
    ("normal", "问题 4：GIF 上传后效果不对。"),
    ("normal", "排查：帧顺序是否正确；FPS 是否过快或过慢；GIF 是否太长导致超出空间；原图比例是否和 160×80 相差过大。"),
    ("normal", "问题 5：屏幕上显示的按键名称不对。"),
    ("normal", "排查：检查“按键描述”内容。因为键盘屏幕优先显示描述；如果描述为空，才会回退到系统自动生成的标签。"),
    ("heading1", "七、给同事的快速示例"),
    ("normal", "示例 A：设置复制键"),
    ("normal", "模式配置 -> 选 Key 1 -> 描述填 CTRL_C_COPY -> 按键类型选 快捷键 -> 添加 Left Ctrl -> 添加 C -> 应用按键到设备。"),
    ("normal", "示例 B：设置宏复制键"),
    ("normal", "模式配置 -> 选 Key 2 -> 描述填 MACRO_COPY -> 按键类型选 宏 -> 按下 Left Ctrl -> 按下 C -> 延时 30 -> 释放 C -> 释放 Left Ctrl -> 释放全部按键 -> 应用按键到设备。"),
    ("normal", "示例 C：上传开机动图"),
    ("normal", "模式配置 -> 切到目标模式 -> 动画管理 -> 添加 GIF -> 调整 FPS -> 播放预览 -> 上传到设备 -> 文件 -> 保存到设备。"),
]


def paragraph(text: str, style: str = "", bold: bool = False, size: int | None = None, color: str | None = None, spacing_after: int = 120) -> str:
    text = escape(text)
    run_props = ""
    if bold:
        run_props += "<w:b/>"
    if size is not None:
        run_props += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    if color is not None:
        run_props += f'<w:color w:val="{color}"/>'
    p_props = f'<w:spacing w:after="{spacing_after}"/>'
    if style:
        p_props = f'<w:pStyle w:val="{style}"/>' + p_props
    return f'<w:p><w:pPr>{p_props}</w:pPr><w:r><w:rPr>{run_props}</w:rPr><w:t xml:space="preserve">{text}</w:t></w:r></w:p>'


body_xml = []
for kind, text in PARAGRAPHS:
    if kind == "title":
        body_xml.append(paragraph(text, style="Title", bold=True, size=32, spacing_after=180))
    elif kind == "subtitle":
        body_xml.append(paragraph(text, style="Subtitle", size=22, color="666666", spacing_after=180))
    elif kind == "heading1":
        body_xml.append(paragraph(text, style="Heading1", bold=True, size=28, spacing_after=140))
    elif kind == "heading2":
        body_xml.append(paragraph(text, style="Heading2", bold=True, size=24, spacing_after=120))
    elif kind == "tip":
        body_xml.append(paragraph("提示：" + text, style="Tip", size=21, color="1F4E79", spacing_after=140))
    else:
        body_xml.append(paragraph(text, style="Normal", size=21, spacing_after=90))

section_xml = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'

document_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk" xmlns:wne="http://schemas.microsoft.com/office/2006/wordml" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" mc:Ignorable="w14 w15 wp14"><w:body>{''.join(body_xml)}{section_xml}</w:body></w:document>'''

styles_xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:eastAsia="微软雅黑" w:hAnsi="Calibri" w:cs="Calibri"/></w:rPr></w:rPrDefault>
    <w:pPrDefault><w:pPr/></w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:rPr><w:color w:val="666666"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/><w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Tip"><w:name w:val="Tip"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="1F4E79"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:style>
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
  <dc:title>Vibecoding Keyboard 实操指南</dc:title>
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
