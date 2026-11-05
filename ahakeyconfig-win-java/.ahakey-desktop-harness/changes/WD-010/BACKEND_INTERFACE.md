# WD-010 云端接口与 AhaType 行为

默认服务地址：`https://956798.xyz/prod-api`。环境变量依次读取 `VIBE_TYPELESS_API_BASE`、`VIBE_API_BASE`；未设置时使用默认地址。

| 方法与路径 | 客户端发送内容 | 用途 |
| --- | --- | --- |
| POST `/api/v1/auth/login` | JSON `phone`、`password` | 登录并取得会话 |
| POST `/api/v1/auth/register` | JSON `phone`、`password` | 注册；无有效会话时需手动登录 |
| GET `/api/v1/auth/users/me` | Bearer 会话 | 账号、服务有效期、适用额度及套餐策略 |
| POST `/api/v1/typeless/process` | Bearer 会话；JSON `text` | 整理最终识别文字 |
| POST `/api/v1/coupon/redeem` | Bearer 会话；JSON `code` | 将兑换计入确认时的账号 |
| POST `/api/v1/payment/wechat/native` | Bearer 会话；JSON `plan` | 创建所选微信套餐订单 |
| GET `/api/v1/payment/wechat/order-status?outTradeNo=...` | Bearer 会话；订单号 | 查询支付结果 |

AhaType 请求示例（占位内容，不含凭据）：

```json
{"text":"本地识别得到的最终文字"}
```

客户端接受 HTTP 200、业务 `code` 为 `0` 或 `200`，读取 `data.text` 或兼容的 `data.result`。先等待整理，再输出一次结果；网络/服务/额度等失败时回退一次原文。请求超时20秒，连接超时15秒。取消、开始下一次录音或退出/切换账号后，旧请求不得迟到输出。系统 Win+H 路径保持原有行为。

接口发送文字，不发送录音音频。账号凭据通过 Windows 用户级 DPAPI 保护。微信充值按旧版套餐弹窗、独立二维码与轮询流程恢复；真实付款/兑换没有由 Agent 执行。

1.0.19 的实际包未接通上述整理调用；WD-010 已接入真实生产调用链，并用本地 HTTP 替身及捕获输出验证成功、失败、20秒超时与并发取消。这证明客户端接线和处理逻辑，不能证明线上账号权益、后端模型效果或实际付款成功。现有仓库资料没有给出服务器内部使用的模型、提示词或部署代码，不能从接口名称推断。

实际成品身份与验证范围以本轮构建收据和交付记录为准；本文件本身不是 EXE 或真机验收回执。
