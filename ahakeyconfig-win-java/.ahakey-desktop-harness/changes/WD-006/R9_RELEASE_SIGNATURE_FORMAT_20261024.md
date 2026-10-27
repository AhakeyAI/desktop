# AhaKey Release Signature v1（R9实施字节契约）

适用固定RSA3072公钥、SHA256withRSA（RSASSA-PKCS1-v1_5）。这是待实现/验证的工程规范，不是验签或安装通过证明。

文件严格为 `original_exe_prefix || payload || signature || footer`。prefix保留原EXE全部字节与原有overlay，不改MSI。所有整数无符号小端；解析时以long检查范围/减法，不能使用会溢出的加法。整包本地上限2GiB。

payload（64..2048字节）：8字节ASCII `AHAKSIG1`（用途及版本）；u64 prefixLength；32字节prefix SHA256；随后按唯一顺序六个字符串：version、variant、arch、product、upgradeCode、productCode。每项为u16 UTF-8字节数+原始UTF-8字节，1..128字节，严格UTF-8解码，禁止NUL/控制字符；拒绝额外字段/尾随字节。version必须规范三段非负十进制；variant=lite或local-model，arch=x64，product=AhaKeyStudio，两个GUID用标准花括号格式。签名覆盖上述payload原始字节，不能重序列化后验。

signature固定384字节，不存算法可选项，不带远程公钥。footer固定16字节：ASCII `AHAKEND1` 八字节 + u32 payloadLength + u32 formatVersion=1，必须紧贴EOF。由EOF读长度，定位signature/payload，核对payload中prefixLength等于总长减去payloadLength、384、16。不得扫描寻找可用签名，拒绝截断、额外尾部、超长、未知版本、错误key及结构歧义。若prefix末尾本身为同一有效格式footer则拒绝重复签名，签名脚本不对已签包重复签名。

Java和worker均以固定公开参数建立RSA公钥，先校验格式/有界长度、验原始payload签名，再流式核对全部prefix摘要。整个封装文件SHA256/长度只在此后生成供握手锁定；它们不替代发行签名。包内MSI实际version/variant/arch/product/UpgradeCode/ProductCode须与签名及选中目录目标一致。worker的信任根绝不来自request字段。

跨语言向量：`R9_RELEASE_SIGNATURE_VECTOR_20261024.json`，由.NET临时RSA3072测试密钥签名；仅记录公开参数、非生产样例payload/signature和测试prefix，私钥不保存。后续Java必须验此向量；Java生成测试签名必须由实际.NET worker验。生产公钥必须不同于测试向量且同时固定到应用和worker。
