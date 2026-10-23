# v1.3.0-route-hf01 窄维护计划

Owner授权：evidence/20261015-wd005-route-maintenance-owner-authorization.md。
目的：修复输入分类不一致，仍由原desktop.py suspend改变路由，不直接写STATE。

## 已核实事实
config_server.json在desktop.source_fingerprint已排除，guardrails.product_path却重新纳入。
其哈希与既有Owner本地BLE配置保留记录一致；不提交/删除/还原该文件。
三份20261010T084508备份为状态清单、未跟踪清单和实际完整Git补丁，不是构建输入。
补丁包含历史WD002 PAUSED、WD004路由及随后产品修改，作为恢复资料永久保留；不拿其旧状态覆盖当前记录。
当前src及pom与HEAD 41c034171e60b2d4962b0adbe8f3cffbf80a0436无差异；
真实产品输入仍须逐字节Git核验，历史补丁不能授权未保存的新源码。

## 精确范围
只修guardrails.py：
1. product_path对既有RUNTIME_ROOT_FILES采用与source_fingerprint一致的排除。
2. committed_inputs接受受保护RECOVERY_EVIDENCE.json中这三个精确文件的非生产分类，
   校验Owner记录、原文件、独立内容副本的哈希和字节，缺失/变化均失败。
3. 分类数据纳入governance_snapshot，仍有seal保护；不忽略整个备份目录，不扩大preserved_foreign。
4. committed_inputs返回非生产恢复证据绑定，suspend/baseline-start/approve共用原入口。
不修改RULES、原始任务start/approval、生产代码、固件；不自动Git。

## 审阅安装
在维护目录准备候选guardrails.py，隔离单元测试后由独立Agent审阅精确候选及安装脚本。
安装脚本只在旧policy_ok通过、Owner/审阅记录及候选哈希一致时执行：
备份旧guardrails/seal/分类数据；安装审阅后的候选和分类；
由新governance_snapshot生成新seal并记录升级收据；失败回滚原字节。
安装不修改STATE或任务目录，不赋予产品批准/PASS。
这属于显式授权并独立审阅的升级，不是在原运行代码上手写seal绕过。

## 必测
已提交产品正常；源码修改/新增/删除未提交仍失败；
未知备份或伪装源码分类失败；已登记备份/内容副本/Owner证据变化失败；
旧运行配置排除一致；新policy覆盖分类；失败没有状态写入。
生产源码/原合同/start/approval安装前后逐字节相同。
安装后再调用原suspend和new；下一前置失败如实报告，不跳过。
