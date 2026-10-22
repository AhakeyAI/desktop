# WD-005 正式产物DLA核验与证据适用性

日期：2026-10-22，DLA。仅只读核验和治理记录，不启动程序。

- 正式token：20261022T004444327311Z-731fe2。
- candidate：e08524cc07077a06d34b79130ddea074355ea2fb。
- BUILD_RECEIPT SHA256：b92ceb89c18f7ecf127c724328090b7b002b458f67205037f4594ba3c7cd7a18。
- 主JAR SHA256：f63f816586d88f7ee44da2c40be419b408948c6b717bfe26a47e90a719af1f1c。
- 19个运行文件、8个回执日志/记录、工具BUILD_REPORT以及LOG_MANIFEST的23份详细证据哈希/大小独立核对一致。
- 正式源码前后为98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9，与候选和已测Preview工作区代码身份一致。

实际读取package完整日志和身份输出：JDK17.0.19、Maven3.9.12，离线增量package退出0；类已是最新，未重新编译，测试跳过。656项仅原R9执行证据。6项既有JavaFX模型warning保留。包不附JRE、桥接或模型；model.enabled来自ModelConfig默认false，而非假称properties显式设置该字段。

DLA用独立ZIP逐条字节比较重验：178条目无增删/重复，173条目相同；4份文本只CRLF/LF；CanvasPane.class唯一两处等长Utf8调试变量名称，内存替换后全字节相同。读取javap差异，名称为LocalVariableTable/常量池调试名称，不是执行指令或配置值。18份依赖逐字节相同，所有应用class为major61，Main入口存在。未修改任何产物。

因此没有因本次包装产生需要重做功能实现的运行语义差异；原Preview普通Windows/USB结果可作为本次限定收口的适用历史证据。新旧JAR并非字节相同，当前包启动仍未执行，不能将原Preview运行日期/结果改写成今天运行。本次Owner已明确只收已验证正常路径，其他项后置，来源为 evidence/20261022-wd005-limited-closeout-owner-decision.md。

固件正式firmware-admit已绑定固定CP2 Gate和FFB920 HEX；不引入后续CP2.5。Owner已确认的物理身份保留为当次历史确认，不冒充当前设备读取。三项身份哈希在修正新记录录入错误后逐项重验一致，修正前文件已保留。

候选、正式产物、固件身份三项已经具备；正式交付包/范围限定结果/归档仍由后续正式命令生成。未执行Git写入、应用、设备、Hook、烧录或发布。
