# R4：既定 Hook 修正所需 TOML 校验依赖

Owner 授权仍为 ../../evidence/20261103-wd009-hook-fix-owner.md，产品动线和范围不变，不需要 Owner 重复批准实现细节。

DIB 与新独立审阅均确认：手写 TOML 规则不能可靠保证 R3 对合法配置兼容及损坏配置拒写的要求。审阅者在当前实现实际复现 QUOTED_DOTTED=REJECT、DUPLICATE_ALIAS=MATCH；真实本机配置当前可解析，不输出其正文。采用本机已有完整缓存的成熟 TOML 解析器替换手写通用校验，避免扩大自研解析器。

新增 allowed_path 仅 pom.xml，添加 org.tomlj:tomlj:1.0.0 及其既有传递依赖。其余生产仅 HookInstaller/TopBar，J014、high_impact 独立审阅、隔离测试和完整 EXE 交付保持。原 R3 Contract/change 原字节已保存 contract-revisions/r3-inputs-before-parser/。不修改治理工具或旧批准，不安装、不写真实 Hook、不 Git 写、不联网下载模型。
