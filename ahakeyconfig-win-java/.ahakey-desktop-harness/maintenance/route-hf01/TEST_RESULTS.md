# 隔离维护测试

执行命令：python .ahakey-desktop-harness/maintenance/route-hf01/test_route_guards.py
前两次在受限沙箱内因临时目录ACL导致16用例无法初始化，不能算测试失败已修或通过。
经工具权限审批后重跑：16个用例全部通过，退出0，耗时1.241秒。
覆盖源码新增/修改/删除阻塞、未知备份阻塞、分类伪装阻塞、原件/内容副本/Owner变化阻塞、
运行配置筛选一致、分类受policy seal保护、失败不写STATE。
此为Python Harness隔离测试，不是Java构建、产品验证、设备测试或安装后的验收。
Git树读取采用测试替身，无Git写入。安装后仍需真实只读Git blob核验。

安装器隔离测试：python .ahakey-desktop-harness/maintenance/route-hf01/test_installer.py。
首次夹具缺config_server.json，1通过/1失败/1错误；补齐夹具后重跑，3项全部通过，退出0，1.172秒。
验证成功安装仍不改任务/产品、保存检查失败恢复原guard/seal、审阅工件被改时写入前拒绝。
终端“installed”来自临时夹具，不是此时真实安装；真实安装必须另有INSTALL_RECEIPT。
