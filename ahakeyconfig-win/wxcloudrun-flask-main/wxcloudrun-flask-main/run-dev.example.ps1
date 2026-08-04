# Windows 本地开发启动示例脚本
# 用法：
# 1. 复制为 run-dev.ps1
# 2. 根据你的环境修改下面变量
# 3. 在项目根目录执行：.\run-dev.ps1

$env:FLASK_DEBUG = "1"
$env:MYSQL_USERNAME = "root"
$env:MYSQL_PASSWORD = "1234"
$env:MYSQL_ADDRESS = "127.0.0.1:3306"
$env:MYSQL_DATABASE = "vibe_keyboard"
$env:JWT_SECRET = "local-dev-change-me"
$env:ADMIN_PHONES = "13800138000"

# 可选：方舟推理
# $env:ARK_API_KEY = ""
# $env:ARK_MODEL_ID = ""
# $env:ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"

python run.py

