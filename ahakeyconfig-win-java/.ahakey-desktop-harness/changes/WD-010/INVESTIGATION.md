# WD-010 云端账号及 AhaType 调查（2026-11-04）

## 结论与证据

当前工作区及 1.0.19 包的本地识别最终输出路径，没有接入 AhaType 云端整理。不是已证实的服务器宕机或账号过期问题。

- `src/main/java/com/example/ahakey/view/TopBar.java:283` 创建云端账号菜单但未绑定 onAction；刷新菜单仅调用 `studioState.toggleAhaType(当前值)`。
- `src/main/java/com/example/ahakey/model/StudioState.java:498` 的 toggleAhaType 仅写 BooleanProperty 和提示文字，不调用网络。默认开启和“云端整理已启用”不能证明实际可用。
- `src/main/java/com/example/ahakey/service/VoiceInputManager.java:143` 的 onFinal 只 trim，再交给 callback 和 KeyboardInjector/textOutput；没有 AhaTypeService、认证检查或云端后处理。
- 当前 src 中没有旧版 AhaTypeService、AhaTypeConfig、CloudAccountManager、CloudAccountDialog。没有证据表明当前系统 Win+H 路径经过这些客户端接口；本结论不否认语音识别引擎自身可能产生标点。

## 实际包隔离验证

输入：`target/WD009-Preview-R4-LocalModel-1.0.19/input/ahakey-studio-1.0.0.jar`。
SHA256：`22d37934b5ad79f3ca3eb41e053642af4bb1adbf084a5e1c0b631b3e78af1f95`。
JAR 文件名来自 1.0.19 Preview 构建目录，不靠文件名猜版本。

探针使用实际包的 StudioState 与 VoiceInputManager；替身只替代录音源和键盘输出。无账户、真实音频、设备、网络或支付操作。源码和日志在本目录 evidence；仅编译临时探针，不构建产品。
实际命令：JDK 17 javac 以包 JAR/lib 为 classpath 编译 Wd010AhaTypeProbe.java，随后 java -Duser.home=隔离目录 -cp 探针classes;包JAR;包lib/* com.example.ahakey.service.Wd010AhaTypeProbe。

实际输出：
```
OBSERVED ahaTypeEnabled=false output=[um tomorrow tomorrow send the report]
OBSERVED ahaTypeEnabled=true output=[um tomorrow tomorrow send the report]
MISSING packaged AhaTypeService
Observation only: no live cloud request, microphone, keyboard injection or GUI click.
```

这验证实际类的输出路径与类缺失，不是云端优化效果评测，也没有冒充 GUI 点击复现。菜单证据来自源码。diagnosing-bugs 的复杂假设/线上仪表化及修复后回归阶段暂不执行：本轮为 CHANGE 调查，直接发现缺失实现，未进行生产修复。DIB 需在真实菜单与输出接缝建立可失败的测试再修复。

## 历史定位

只读本地 Git 历史，未修改参考分支：
- `6a04439c`（2026-09-18）：恢复 AhaType 客户端和账号状态。
- `0ce5c5cd`、`10171efa`、`94fd2398`：补齐持久化并阻止旧响应恢复已退出会话。
- `98f19a9a`（2026-09-20）：恢复账号和支付流程。
- `e9f3fba7`：账号刷新细化，含云端服务、账号窗口及测试；origin/eternal-dev 包含此提交。
- `3aa2a6ca`（2026-10-22）：将 Windows Java 实现带入 main。
- `f6c7a5c8`（2026-10-24）：修正取消/发行集成，含服务有效期和失败处理。

目前在 main-anpx 已查询的 Java 文件历史中未定位到这套实现；确实找到的是 eternal-dev 和 main 系列。历史代码存在不等于当前环境真机通过。恢复应逐块迁移，不能整体覆盖现有语音引擎、VoiceInputManager 或 TopBar，避免丢失 WD009 行为。

## 旧客户端接口契约

来自 f6c7a5c8 的 AhaTypeService / CloudAccountManager，不是当前后端实时探测或后端实现说明。
默认 base：`https://956798.xyz/prod-api`。环境变量优先级：`VIBE_TYPELESS_API_BASE` → `VIBE_API_BASE` → 默认值。登录后携带 `Authorization: Bearer <token>`。请求 timeout 20 秒，连接 timeout 15 秒。

| 功能 | 方法与相对路径 | 主要请求字段 |
| --- | --- | --- |
| 登录 | POST /api/v1/auth/login | phone、password |
| 注册 | POST /api/v1/auth/register | phone、password |
| 账号/额度刷新 | GET /api/v1/auth/users/me | Bearer token |
| 识别文字整理 | POST /api/v1/typeless/process | text |
| 兑换码 | POST /api/v1/coupon/redeem | code |
| 微信支付订单 | POST /api/v1/payment/wechat/native | plan |
| 支付状态 | GET /api/v1/payment/wechat/order-status?outTradeNo=… | 订单号及 Bearer token |

文字整理示意（非真实账户、非实测返回）：
```http
POST https://956798.xyz/prod-api/api/v1/typeless/process
Authorization: Bearer <token>
Content-Type: application/json; charset=utf-8

{"text":"嗯那个明天下午三点开会"}
```
客户端接受 HTTP 200 且业务 code 为 0 或 200，从 `data.text` 或 `data.result` 读取非空整理结果。如 `{"code":200,"data":{"text":"明天下午三点开会。"}}` 只是格式示意，不是效果承诺。该接口发送文字，不上传音频。

旧版开关、登录态、服务有效期决定是否请求；关闭、未登录、到期、额度不足、网络/响应异常时回退原文并更新原因。成功时更新返回的额度等信息。退出为本地清理会话，未发现独立 logout API。支付返回 code_url/h5_url、out_trade_no 等，客户端轮询支付状态；创建订单或打开链接不是支付成功。
本次未请求线上接口，未确认后端实现、部署、模型或提示词，不能承诺默认 base 今天仍可用，需后续受控联调。

## 范围、阶段和治理恢复

Owner 已选择“全部恢复旧版功能，包括兑换和充值”。WD-010 正式处于 CHANGE/SCOPE，未实现、未构建、未发新测试包。WD-009 按新排期暂停正式收口，保留 1.0.19 Preview PASS，不标为 CLOSED。
首次 suspend 因此前我追加 AGENTS 分支规则触发 PROTECTED_GOVERNANCE_CHANGED。已将规则完整保留为 `.ahakey-desktop-harness/OWNER_GIT_BRANCH_POLICY.md`，备份追加后原文，并将 AGENTS 恢复到原 seal 中精确 SHA256 `63e9e27b3968513caaed2bac35c25ac206b37fe7d8a08b8f139dc4ca4a223f8c`，未改 seal、校验器或受保护规则。随后正式 suspend/new/journey-register/change-meta 成功。Git 只读、pre-push 限制保留。
