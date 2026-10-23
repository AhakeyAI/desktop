# WD-006 Owner 批准

前序具体方案：以已合入 main 的 ahakeyconfig-win-model-java 为非 eternal 来源，最小范围补齐 WD-005 的本地语音，取得配套模型/JNI，验证后打包 model-bundled EXE。

Owner 在核实 main/提交作者后明确回复：
> 允许按照这个已经合入main分支的版本补齐模型

持续约束：不使用 eternal 的语音、UI、云服务等代码；仅官方 main PR #172 为本次语音参考。允许必要模型/JNI获取、隔离构建及离线验证，不授权安装、真实麦克风采集、设备写入或公开发布。既有 Git 保存授权用于将必要候选保存到 win-zxy-harness，不触及其他分支。

与已暂停 WD-002 隔离：保留既有文件字节和外来 dirty，不重置其合同或状态；本轮只改语音内部、依赖、配置和隔离打包/测试。WD-005 历史保持不变。
