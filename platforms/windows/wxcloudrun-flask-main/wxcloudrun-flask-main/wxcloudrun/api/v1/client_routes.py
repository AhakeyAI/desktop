"""
API v1 - 客户端发布相关路由。
职责：
1. 向桌面端暴露配置工具版本检查接口。
2. 通过环境变量控制是否提示更新，适配微信云托管部署。
"""

import re

import config
from flask import request

from wxcloudrun.api.v1.shared import bp
from wxcloudrun.response import make_succ_response


def _version_parts(version: str):
    text = (version or "").strip()
    if not text:
        return ()
    return tuple(int(x) for x in re.findall(r"\d+", text))


def _has_update(current_version: str, latest_version: str) -> bool:
    current = (current_version or "").strip()
    latest = (latest_version or "").strip()
    if not latest:
        return False
    if not current:
        return True

    current_parts = _version_parts(current)
    latest_parts = _version_parts(latest)
    if current_parts and latest_parts:
        max_len = max(len(current_parts), len(latest_parts))
        current_parts = current_parts + (0,) * (max_len - len(current_parts))
        latest_parts = latest_parts + (0,) * (max_len - len(latest_parts))
        return latest_parts > current_parts

    return latest != current


@bp.route("/client/config-tool/release", methods=["GET"])
def config_tool_release():
    """
    返回键盘配置工具的发布信息。
    查询参数：
    - current_version: 客户端当前版本号
    """
    current_version = (request.args.get("current_version") or "").strip()
    latest_version = config.CONFIG_TOOL_LATEST_VERSION
    download_url = config.CONFIG_TOOL_DOWNLOAD_URL
    release_notes = config.CONFIG_TOOL_RELEASE_NOTES

    payload = {
        "has_update": _has_update(current_version, latest_version),
        "latest_version": latest_version,
        "release_notes": release_notes,
        "download_url": download_url,
    }
    return make_succ_response(payload)
