# WD-005 第七轮原 DLA 实际复审

日期：2026-10-20。revision4 / round7。结论：原 DLA actual review PASS，允许进入 Owner Preview 构建准备；不是 formal high-impact fresh、构建、真机或 UAT PASS。

## 固定输入及累计范围

- pack：reviews/20261020T063958914747Z-fa224e/PACK.json。
- canonical pack SHA256：d835f4929b834b48d3a194936b535d4b3d94fb3de480c192ef3d382c730833a7。
- 源码指纹：e10b4d65ad9b3f62221b7790b659c09429243a96a43a169db575dce6b4c18e8a。
- 原起点41c034171e60b2d4962b0adbe8f3cffbf80a0436保留；HEAD f595262207796dbf325cb9951ed3dc02b4887362仅源码存档。
- 累计33文件当前字节与固定pack全部一致，无缺失起点字节。26文件与第五轮after逐字节一致，承接同字节历史审阅并复核本轮接口影响；另外7文件逐hunk审阅。不是把HEAD无差异当作没有累计实现，也不是宣称本轮重做了所有硬件验收。

## Standards / Spec

两个辅助reader分别检查标准和测试规格，均未发现确定的新增阻断问题；原DLA负责最终调用链复核。辅助reader不构成本轮formal fresh。

生产改动仅BleManager:992增加protected isUsbDevicePresent，默认return原静态发现；998和1026两处替换。重读构造、connect、sendCommand/writeData/queryStatus、lease释放/reset、exchangeDisplay及补发链，生产顺序/异常/锁/连接策略均未改变。构造没有真实枚举/连接；生产Socket仅位于connect线程。测试final子类在创建线程前拒绝connect。

OfflineBleManager完整内存USB覆盖open/isOpen/sendCommand/sendData/close，未调用super；发现入口不触及静态原生发现。FakeSession和原解析用例全部使用安全构造，构造失败不返回未隔离实例。没有覆写sendCommand、exchangeDisplay、flush或reset逃避被测逻辑。仅USB用例开启内存USB；BLE仍使用关闭USB/发现false和内存TCP流，受控IOException继续经过真实BLE分支。

lease关闭和reset不替换回真实USB，不丢弃发现策略。A10用于避开硬件的假readUncertain已删除；真正未知ACK隔离用例仍保留。新增隔离检查涵盖两处发现、connect阻断、reset后发送、lease释放及匿名自身终态补发。R5-F1关闭。

R4-F1/F2/F3继续保持：可信终态先更新事实再判断SINGLE显示占用；匿名占用与无占用分离；失败补发不刷新原事件TTL。上传异常在lease释放前设恢复隔离、FX连接/操作身份与旧写入过滤链保持，未发现本轮确定回归。

## 证据与限制

检查表16份证据哈希全部匹配；verification四项与当前批准、round7和源码一致。DIB日志支持离线编译退出0及507项断言（443项本轮重跑+64项新增），不是复用旧443项PASS。根EXECUTION_REPORT与report_sha仍为冻结历史基报告，本轮结果来自第七轮报告/检查表和直接日志。

不把覆盖缺口当作生产故障，也不豁免：
- DisplayConfigChecks旧代次回复检查未强断言不入队。
- MemoryUsb未保存onFrame，直接解析注入不能证明真实USB旧接收回调隔离。
- IOException补发TTL主要验证TCP，未独立覆盖USB发送异常。
- UP-01/02真机根因、来源缺失事件、RT-03固件回退、BLE性能及完整应用继续待办。

这些限制不否定本轮静态封闭I/O结论，也不支持宣称USB/BLE真实链通过。DLA没有运行测试、真实应用、设备操作或构建；没有生产/测试/桥接/固件/Git修改。

## 路由与历史

新增本MD和同名JSON为本轮实际审阅记录。为Preview工具读取当前入口，保留根REVIEW原字节后把入口指向本轮JSON；旧审阅/固定pack/fresh不覆盖、不伪装新绑定。原根REVIEW SHA256为8226b3619827d3ce17226b7100cf8b5aa045e034c26266930359eb5c26d38856。

formal review check仍需新pack的独立fresh，不登记formal PASS。按Preview-first规则只开隔离源码构建令牌，不因formal fresh/candidate尚未完成阻止Preview。全局路由由正式工具管理，不手写STATE。本轮Owner明确要求“没问题就推进到Preview打包”，只授权DIB在新快照内构建JAR/classpath，不授权自动启动、安装Hook、设备写入、固件烧录或发布。
