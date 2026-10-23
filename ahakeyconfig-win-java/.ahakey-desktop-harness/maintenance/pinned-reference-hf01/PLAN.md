# WD-005 固定引用维护 pinned-reference-hf01

Owner 授权见 evidence/20261021-wd005-pinned-reference-maintenance-owner-authorization.md。
独立于 WD-005 产品实现，不改变 revision、批准、起点、审阅、源码或验收结果。

## 范围

- 仅在 desktop.reference_inputs 添加明确登记的固定版本读取分支。
- 新增 pinned_references.py 及受治理印章保护的精确 WD-005 引用清单。
- 仅 WD-005 revision5、原 REFERENCES 文件哈希匹配时使用清单；其他任务/引用沿用原严格校验。
- 原九个固件源码引用读取原记录的完整 Git commit/path/blob，不跟随 HEAD 或工作区。
- 三个 gate 引用仍要求原路径、原始 SHA 精确匹配。
- 每个固定源码引用要求原批准字节副本 SHA 精确匹配原 REFERENCES，Git blob/OID/SHA 同时匹配；仅这九个精确绑定文件允许逐字节 CRLF/LF 比较，其他内容差异拒绝。部分 C 文件含历史编码注释，不解码、不替换乱码、不做编码转换。副本用于字节证据，不是新批准。
- 原 header 混合换行仅在重建后 SHA 精确等于原批准时接纳，明确标为重建字节，绝不伪称历史备份。全体副本与 Git blob 归一化后必须相同。
- 固件仓只读。不调用过滤器、hooks、checkout、fetch 或替换对象，不改 local 固件根。
- 缺清单/副本/对象、错误 hash、符号链接、批准变化等均失败关闭。任何新协议内容须正常合同流程。

## 安装

候选在本目录生成，不直接修改运行 helper。隔离单元测试和独立审阅通过后，安装器核对旧 helper/seal、Owner 授权、候选/测试/安装器哈希；加正式写锁，再次核验后备份并原子写入。仅已审阅路径可进入新治理快照；任何失败恢复原字节。STATE 和产品任务历史逐字节保持不变。

安装收据不是产品审阅或测试 PASS。安装后由原 DLA 调用正式 candidate-plan，Git操作仍交Owner。新鲜审阅 JSON 的额外候选保存不通过修改历史 REVIEW 解决。
