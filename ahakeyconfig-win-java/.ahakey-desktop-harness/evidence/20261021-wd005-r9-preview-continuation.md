# WD-005 第九轮 Preview 接续依据

当前Owner直接指派第九轮实际复审，并要求“复审通过后再按正式权限推进新Preview”。沿用20261017-wd005-owner-preview-build-authorization.md中已授权的隔离源码固定、DIB可运行JAR/classpath构建及既有Preview迭代流程；不扩为EXE、运行应用或设备授权。

原DLA实际审阅通过后，允许新增本轮审阅与交接记录，保存旧REVIEW入口的完整原字节后更新当前入口，使用正式preview-open生成本轮token和source，不手写回执或路由。已有Owner关于“允许：保留旧记录，更新当前REVIEW入口”的确认继续按保留历史原则执行。

本记录不修改产品合同、批准或起点，不将旧fresh用于新pack；只允许DIB使用该新令牌隔离构建，不允许DLA自动构建，不允许启动应用、Git写入、Hook、设备连接/写入、烧录或发布。构建失败保存日志回DLA，不修改冻结输入。
