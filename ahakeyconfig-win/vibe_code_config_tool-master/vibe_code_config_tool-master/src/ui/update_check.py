"""启动时异步检查配置工具更新。"""

from typing import Any, Dict, Optional

import requests
from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal

from ..core import cloud_settings
from ..core.app_version import APP_VERSION
from ..core.cloud_api import CloudApi, CloudApiError


class UpdateCheckSignals(QObject):
    finished = Signal(object, str)


class _UpdateCheckRunnable(QRunnable):
    def __init__(self, signals: UpdateCheckSignals):
        super().__init__()
        self._signals = signals

    def run(self):
        try:
            base = cloud_settings.effective_api_base()
            if not base:
                self._signals.finished.emit(None, "")
                return
            api = CloudApi(base, None)
            data = api.config_tool_check_release(APP_VERSION)
            self._signals.finished.emit(data, "")
        except CloudApiError as e:
            self._signals.finished.emit(None, str(e))
        except requests.exceptions.Timeout:
            self._signals.finished.emit(None, "连接超时")
        except requests.exceptions.RequestException as e:
            self._signals.finished.emit(None, str(e))
        except Exception as e:
            self._signals.finished.emit(None, str(e))


def schedule_update_check(signals: UpdateCheckSignals) -> None:
    QThreadPool.globalInstance().start(_UpdateCheckRunnable(signals))


def interpret_update_payload(data: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """若需要提示更新则返回 dict，否则 None。"""
    if not data or not isinstance(data, dict):
        return None
    if not data.get("has_update"):
        return None
    return data
