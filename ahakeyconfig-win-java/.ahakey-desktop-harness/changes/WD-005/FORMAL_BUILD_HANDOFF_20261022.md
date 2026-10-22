# WD-005 正式候选构建回交

日期：2026-10-22，DIB。

正式preflight、build-open、离线package、build-finish已成功，STATE=VERIFY/DELIVERY_PREP，next_actor=DLA。token=20261022T004444327311Z-731fe2。
BUILD_RECEIPT.json SHA256=b92ceb89c18f7ecf127c724328090b7b002b458f67205037f4594ba3c7cd7a18，绑定候选e08524cc07077a06d34b79130ddea074355ea2fb及19个运行文件；已复核所有产物、回执日志和23个细节证据哈希一致。

实际产物绝对目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-005\builds\20261022T004444327311Z-731fe2\runtime-jar-classpath。
主JAR=ahakey-studio-1.0.0.jar，647301字节，SHA256=f63f816586d88f7ee44da2c40be419b408948c6b717bfe26a47e90a719af1f1c。

package为已授权的增量构建，无clean；日志显示class已是最新、未重新编译，Tests are skipped。源码前后98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9一致。656项为此前执行，未冒称本次重跑。详细命令、环境、Main启动配方及外部依赖见BUILD_DETAILS.md；正式BUILD_REPORT由工具生成，冻结执行报告未改。

## 已测Preview对比

对比preview-20261021T024920511394Z-2ae03d，主JAR旧SHA97a5ae072c18a0ed229538fee7766426bd9f6c8ba807607aee10f141efa3052b。
178条目无增删，173条目内容一致但容器元数据不同。4个文本（VoiceInputPanel.fxml/logback.xml/model_config.properties/内嵌pom.xml）只存在CRLF/LF差异，严格UTF-8解码后仅规范化换行即可精确一致。
CanvasPane.class的唯一字节差异为两处常量池Utf8名称：patt3223$temp / patt2763$temp 对应Preview的patt3151$temp / patt2700$temp。仅内存等长替换这两处名称后整份class字节相等；javap证明是LocalVariableTable合成调试变量名称，不是指令或运行常量变化。源码也仅换行不同，位置数字的原因解释属于推断；判定以实际class全字节和反汇编为据。
18个依赖JAR全部字节一致。上述是静态内容解释，不把新旧包误称字节相同，也不代替新包启动/UAT。

DLA追加要求的只读解释已完成，见PREVIEW_DIFFERENCE_ANALYSIS/JAVAP_EXECUTION/JAVAP_DIFFERENCES/CANVAS_SOURCE_COMPARISON及原始输出。javap的中文路径显示头存在乱码，实际输入路径由JAVAP_EXECUTION argv和ARTIFACT_MANIFEST明确，ASCII类结构与内容hash不受影响；原输出原样保留。

本轮没有真实应用启动、设备操作、Hook、固件/桥接修改或Git写入。formal fresh及Owner Preview已有结果保留；正式UAT和验收差额由DLA收口，不自动关闭任务。按Owner已记录的直接接续授权回交原DLA，无需Owner搬运。

## 完整接续提示词

```text
$ahakey-desktop-lead
$ahakey-desktop-harness

角色：DLA；目标窗口：原DLA对话
工作目录：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java
任务：WD-005 revision5 / round9 正式构建核验与交付准备
模式：DELIVERY_PREP

事实：
- 正式build-finish成功；STATE=VERIFY/DELIVERY_PREP，next_actor=DLA。
- token=20261022T004444327311Z-731fe2。
- 候选e08524cc07077a06d34b79130ddea074355ea2fb；源码前后均
  98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- 离线package首次退出0，跳过测试；656项不是本次重跑。
- 19个运行文件；主JAR SHA256：
  f63f816586d88f7ee44da2c40be419b408948c6b717bfe26a47e90a719af1f1c。
- 与已测Preview比较：178条目无增删，173项内容相同；
  4个文本仅CRLF/LF；CanvasPane.class仅两个合成调试变量名不同，
  等长替换后整份class字节相等，javap证据已保存；18依赖逐字节相同。
- 新包并非与Preview字节相同；内容解释不等于新包运行/UAT通过。
- 未启动应用或设备；未修改源码、固件、桥接、规则或执行Git写入。

先读适用AGENTS、Lead/Harness Skills、正式规则、STATE/local和：
C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-005\FORMAL_BUILD_HANDOFF_20261022.md
C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-005\BUILD_RECEIPT.json
以及builds/20261022T004444327311Z-731fe2内：
BUILD_DETAILS.md、ARTIFACT_MANIFEST.json、LOG_MANIFEST.json、
PREVIEW_COMPARISON.json、PREVIEW_DIFFERENCE_ANALYSIS.json、
JAVAP_EXECUTION.json、JAVAP_DIFFERENCES.json及原始反汇编/构建日志。

授权：沿用Owner已授权build-only和直接跨对话接续，进入DLA核验；
不自动获得新包运行、设备测试、Git归档或发布权限。
核对正式回执、候选、全部哈希与5项差异解释，决定既有Preview证据
可复用范围及真实验收差额。固件身份/准入由DLA另行处理，不重做。
运行目录为上述build token下runtime-jar-classpath。
启动配方只记录：JDK17、三个UTF-8参数、Main/classpath，不用java -jar。
包不附JRE、现场桥接或本地模型，不称全功能自包含。

保留UP-01/02、来源缺失事件、RT-03、BLE性能、完整应用及未覆盖项；
原DLA/fresh/Owner Preview已PASS不自动成为正式UAT PASS。
禁止改产品/测试/固件/桥接/Harness、覆盖冻结记录、还原dirty；
不自动重构建、启动应用、安装Hook、连接/写设备、烧录、发布或Git写入。
无需Owner手工搬运；所有结论中文，跨对话接续在正文完整展示Prompt。
```

