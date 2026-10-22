# WS5 发布组合绑定检查（实现中）

对应G53/G54/P02。该维护者工具核对同一发布组合中客户端安装包、固件HEX、目录签名、稳定恢复镜像、预算声明和验收文件的绑定关系；不代表已经真实验收，不替代发布批准。不会生成公钥、正式目录、恢复镜像、签名/公证凭据或用户测试结果。

## 运行

从ahakeyconfig-mac运行：

```sh
swift run -c release ahakey-release-check MANIFEST.json ARTIFACT_ROOT TRUST-KEYS.json MINIMUM-CATALOG-REVISION
```

四个参数均显式传入。信任文件由维护者/CI固定，内容为keyID→base64原始Ed25519公钥的JSON字典，不能从下载的目录中取公钥。最低revision由发布流程记录，必须为正数，不因本地目录较旧自动降低。成功输出JSON摘要、退出0；不一致退出1；参数错误退出2。命令是单独的SwiftPM产品，build.sh仍只打包现有App和Agent，不把维护者工具放进用户App。

## Manifest版本1

`schemaVersion=1`；它与固件存储schema、catalog key、目录payload schema各自独立。入口最大1MiB。

| 字段 | 内容 |
| --- | --- |
| client | version、variant（本轮legacy-macos）、完整40位非空源码commit、installer文件引用 |
| firmware | 正常目标key、完整源码commit、image文件引用 |
| recovery | 稳定恢复目标key、完整源码commit、image文件引用；可以与正常目标相同 |
| catalog | 有签名envelope文件引用，最多2MiB |
| catalogRevision | 必须与实际验签后目录一致，且不低于维护者传入的下限 |
| budgets | codeFlash、ram、w25q三项且不重复；usedBytes/approvedLimitBytes，不允许超限。CodeFlash不得突破现有CH582 448KiB地址限。其余预算上限须来自硬件/构建负责人，不猜测W25Q实装容量或链接器布局 |
| evidence | 以下必需gate的确认结果及文件引用，各gate唯一，最多128项；不接受pending/failed |

所有文件引用统一包含相对path、精确sha256与byteCount。拒绝绝对路径、空/点/父级路径段、反斜线、控制字符、穿出根目录的符号链接、非普通文件、缺失或大小/摘要变化。安装包最大16GiB，按1MiB流式哈希，不整包读进内存；证据单文件最多64MiB。

正常与恢复镜像必须匹配可信目录中对当前客户端/硬件/variant兼容、用户可见的稳定条目；恢复还必须明确recoverySafe。文件名、实际字节数和SHA必须匹配该条目，并使用与App烧录页完全相同的Intel HEX解析、记录校验和、CH582地址上限。两个不同key不能指向同一镜像字节。内置工程1.4.6没有这些发布证明，不能冒充恢复安全候选。

## 证据gate和作用域

必需gate：protocol-governance、mac-core-uat、firmware-budget、firmware-recovery、installer-signing-notarization、compatibility-known-limitations、full-regression。

每份证据声明必须携带result、clientCommit、installerSHA256、firmwareSHA256、recoverySHA256、firmwareSourceCommit、recoverySourceCommit、catalogRevision及report文件引用，与本组合逐项一致。由此防止复用旧安装包的公证说明、旧恢复镜像的测试、其他固件的UAT或其他目录revision的结果。报告文件本身同样按字节数和SHA绑定。

输出摘要包含三端源码commit、安装包/正常HEX/恢复HEX/目录摘要、实际验签公钥的SHA256、目录revision和已绑定gate列表；不把已知限制省略成“无问题”。

## 证明边界

工具证明的是文件完整性、目录可信性、兼容性规则以及声明之间的一致性。它不检查Git对象是否存在、不独立重编固件、不测量实际Flash/RAM/W25Q、不挂载安装包核对内容、不替代Apple签名/公证服务，也不阅读报告后判断实体操作是否真实完成。以上均由各原始gate产生可审查证据，维护者最终核对内容并批准发布。CLI成功文本明确保留这一边界，不能以退出0自动发布。

局部测试使用临时生成的测试签名密钥、合成安装包/证据和小HEX，仅测试绑定逻辑，所有文件测试后删除；不提交私钥或伪造用户验收物。本轮7项组合测试加既有目录/HEX测试共26项通过，包含真实启动CLI的成功/拒绝路径、错误证据作用域、坏签名/revision、越界路径/符号链接、改动文件、超预算/恢复身份、签过名但HEX格式错误、2.5MB流式文件。完整回归与正式发布验收仍按开发完成后集中执行。

两轴代码审查通过。HEX校验器迁移已逐字比较（仅访问修饰符改变），旧App调用用typealias保留；26项测试含旧HEX/目录回归，未改变用户烧录页行为。正式发布流水线接入及真实发布材料仍待后续，不因维护者工具完成关闭G54。
