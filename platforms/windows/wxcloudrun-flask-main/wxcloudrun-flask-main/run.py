"""
服务启动入口。

职责：
1. 读取项目根目录 `.env`。
2. 导入并启动 Flask 应用实例。

用法：
- python run.py
- python run.py 0.0.0.0 5000
"""

import sys
from pathlib import Path

try:
    from dotenv import load_dotenv

    # 优先加载项目目录下 .env，避免运行环境变量污染。
    load_dotenv(Path(__file__).resolve().parent / ".env", override=True)
except ImportError:
    pass

from wxcloudrun import app


if __name__ == "__main__":
    # 支持通过命令行传入 host 与 port，便于本地调试。
    host = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    app.run(host=host, port=port)
