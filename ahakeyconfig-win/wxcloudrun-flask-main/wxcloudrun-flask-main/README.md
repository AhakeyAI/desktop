# wxcloudrun-flask 后端服务

## 项目定位

本项目是 VibeKeyboard 的云端后端服务，负责：
1. 用户注册登录与 JWT 鉴权。
2. 配额策略、套餐与周期管理。
3. 兑换码生成与兑换。
4. 微信支付下单与回调。
5. 方舟推理转发与文本处理接口。

## 已完成的重构（本次同步）

已将 `wxcloudrun/api/v1/routes.py` 拆分为 5 个业务子路由文件，并新增共享层，原有接口路径保持不变。

### 路由拆分结果
1. `auth_routes.py`：注册、登录、`/users/me`
2. `admin_routes.py`：配额策略管理、批量生成兑换码
3. `coupon_routes.py`：兑换码兑换
4. `inference_routes.py`：chat-completions、typeless 文本处理
5. `payment_routes.py`：微信支付下单、查单、回调
6. `shared.py`：共享 `bp`、鉴权工具、兑换码通用逻辑、常量
7. `routes.py`：聚合入口（只负责导入子模块并导出 `bp`）

## 最新目录结构

```text
wxcloudrun-flask/
├─ run.py
├─ config.py
├─ requirements.txt
├─ Dockerfile
├─ container.config.json
└─ wxcloudrun/
   ├─ __init__.py
   ├─ extensions.py
   ├─ models.py
   ├─ repositories.py
   ├─ route_registry.py
   ├─ response.py
   ├─ database_bootstrap.py
   ├─ api/
   │  └─ v1/
   │     ├─ __init__.py
   │     ├─ routes.py
   │     ├─ shared.py
   │     ├─ auth_routes.py
   │     ├─ admin_routes.py
   │     ├─ coupon_routes.py
   │     ├─ inference_routes.py
   │     └─ payment_routes.py
   ├─ services/
   │  ├─ __init__.py
   │  ├─ auth_service.py
   │  └─ quota_service.py
   └─ integrations/
      ├─ __init__.py
      ├─ ark_client.py
      ├─ wechat_native.py
      └─ wechat_notify.py
```

## `__init__.py` 是做什么的

在 Python 里，`__init__.py` 是“包入口文件”，作用是：
1. 声明该目录是可导入的 Python 包。
2. 决定包对外暴露哪些对象（例如 `bp`）。
3. 可放初始化逻辑，但建议保持轻量，避免副作用过重。

本项目中：
1. `wxcloudrun/__init__.py`：应用工厂入口（创建 Flask app）。
2. `wxcloudrun/api/v1/__init__.py`：对外暴露 `bp`，供上层统一注册。

## 运行方式

```powershell
cd wxcloudrun-flask
pip install -r requirements.txt
python run.py
```

默认监听：`0.0.0.0:5000`

## 配置说明（完整环境变量）

### Flask
1. `FLASK_DEBUG`

### MySQL
1. `MYSQL_USERNAME`
2. `MYSQL_PASSWORD`
3. `MYSQL_ADDRESS`
4. `MYSQL_DATABASE`
5. `MYSQL_AUTO_CREATE_DATABASE`

### JWT / 管理员
1. `JWT_SECRET`
2. `JWT_EXPIRES_SECONDS`
3. `ADMIN_PHONES`

### 方舟推理
1. `ARK_API_KEY`
2. `ARK_BASE_URL`
3. `ARK_MODEL_ID`

### 兑换码与配额
1. `COUPON_CODE_PEPPER`
2. `FREE_COUPON_DAYS`
3. `COUPON_REDEEM_WINDOW_MINUTES`
4. `COUPON_REDEEM_MAX_FAILS`
5. `COUPON_REDEEM_LOCKOUT_MINUTES`

### 微信支付（由 integrations 层读取）
1. `WECHAT_PAY_APPID`
2. `WECHAT_PAY_MCHID`
3. `WECHAT_PAY_SERIAL_NO`
4. `WECHAT_PAY_PRIVATE_KEY_PATH`
5. `WECHAT_PAY_NOTIFY_URL`
6. `WECHAT_PAY_API_V3_KEY`

## 路由扩展规范（后续开发）

当新增业务域时，建议按以下方式扩展：
1. 新建 `*_routes.py`（如 `device_routes.py`）。
2. 复用 `shared.py` 中的通用方法，避免重复实现鉴权与通用校验。
3. 在 `routes.py` 中增加对应模块导入，完成注册。
4. 复杂业务逻辑下沉到 `services/`，路由层保持“薄控制器”。

