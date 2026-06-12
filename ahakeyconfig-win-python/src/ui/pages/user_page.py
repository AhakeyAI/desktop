"""云端账号：登录、配额展示、充值与兑换（管理端请使用独立工具 vibe_admin）。"""

import json
from typing import Any, Dict, Optional

import requests
import threading
import time

from PySide6.QtCore import QObject, QRunnable, Qt, QThreadPool, QUrl, Signal, QTimer
from PySide6.QtGui import QDesktopServices, QImage, QPixmap
from PySide6.QtWidgets import (
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from ...core.cloud_api import CloudApi, CloudApiError
from ...core import cloud_settings
from ...core import typeless_store


class _UsersMeSignals(QObject):
    """在主线程接收后台线程的 /users/me 结果。"""

    finished = Signal(object, str, int, int)  # me|None, err_msg, seq, http_status(0=鏈煡)


class _UsersMeRunnable(QRunnable):
    def __init__(
        self,
        api_base: str,
        token: str,
        signals: _UsersMeSignals,
        seq: int,
    ):
        super().__init__()
        self._api_base = api_base
        self._token = token
        self._signals = signals
        self._seq = seq

    def run(self):
        try:
            api = CloudApi(self._api_base, self._token)
            me = api.users_me()
            self._signals.finished.emit(me, "", self._seq, 200)
        except CloudApiError as e:
            self._signals.finished.emit(None, str(e), self._seq, e.status_code or 0)
        except requests.exceptions.Timeout:
            self._signals.finished.emit(
                None,
                "连接服务器超时（云托管冷启动时首次请求可能较慢），请稍后点击「刷新」重试。",
                self._seq,
                0,
            )
        except requests.exceptions.RequestException as e:
            self._signals.finished.emit(None, str(e), self._seq, 0)
        except Exception as e:
            self._signals.finished.emit(None, str(e), self._seq, 0)


class _RechargeOrderSignals(QObject):
    """在主线程接收支付订单轮询结果。"""

    finished = Signal(object, str)  # cancel_event, status


class _RechargeOrderRunnable(QRunnable):
    def __init__(
        self,
        api_base: str,
        token: str,
        out_trade_no: str,
        cancel_event: threading.Event,
        signals: _RechargeOrderSignals,
        status_timeout_s: int = 180,
        poll_interval_s: float = 2.0,
    ):
        super().__init__()
        self._api_base = api_base
        self._token = token
        self._out_trade_no = out_trade_no
        self._cancel_event = cancel_event
        self._signals = signals
        self._status_timeout_s = status_timeout_s
        self._poll_interval_s = poll_interval_s

    def run(self):
        start = time.time()
        try:
            api = CloudApi(self._api_base, self._token)
            while not self._cancel_event.is_set():
                try:
                    data = api.payment_wechat_order_status(self._out_trade_no)
                    status = (data.get("status") or "").strip().lower()
                    if status in {"paid", "failed"}:
                        self._signals.finished.emit(self._cancel_event, status)
                        return
                except Exception:
                    # 轮询过程中忽略单次失败（例如冷启动慢/网络抖动）
                    pass

                if time.time() - start >= self._status_timeout_s:
                    self._signals.finished.emit(self._cancel_event, "timeout")
                    return

                # 可在取消时尽快退出
                self._cancel_event.wait(self._poll_interval_s)
        except Exception:
            # 极少数异常兜底
            if not self._cancel_event.is_set():
                self._signals.finished.emit(self._cancel_event, "error")


def _apply_quota_progress(bar: QProgressBar, used: int, limit: int) -> None:
    used = int(used or 0)
    limit = int(limit or 0)
    if limit <= 0:
        bar.setRange(0, 1)
        bar.setValue(1)
        bar.setFormat("已用 {} · 无上限".format(used))
    else:
        bar.setRange(0, limit)
        bar.setValue(min(max(used, 0), limit))
        bar.setFormat("%v / %m")


def _policy_quota_visibility(pol: Dict[str, Any]) -> tuple:
    """返回是否显示 日/周/月 配额行。若服务端未下发策略字段，则三项都显示（兼容旧接口）。"""
    d = pol.get("enable_daily")
    w = pol.get("enable_weekly")
    m = pol.get("enable_monthly")
    if d is None and w is None and m is None:
        return True, True, True
    return bool(d), bool(w), bool(m)


def _make_quota_block(title: str):
    w = QWidget()
    lay = QVBoxLayout(w)
    lay.setContentsMargins(0, 0, 0, 0)
    lay.setSpacing(4)
    title_lbl = QLabel(title)
    bar = QProgressBar()
    bar.setMinimumHeight(22)
    bar.setTextVisible(True)
    lay.addWidget(title_lbl)
    lay.addWidget(bar)
    return w, bar


class UserPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._me: Optional[Dict[str, Any]] = None
        self._refresh_seq = 0
        self._users_me_signals = _UsersMeSignals(self)
        self._users_me_signals.finished.connect(self._on_users_me_finished)
        self._recharge_dialog: Optional[QDialog] = None
        self._recharge_cancel_event: Optional[threading.Event] = None
        self._recharge_result: Optional[str] = None
        self._recharge_signals = _RechargeOrderSignals(self)
        self._recharge_signals.finished.connect(self._on_recharge_order_finished)

        self._quota_poll_timer = QTimer(self)
        self._quota_poll_timer.setInterval(2000)
        self._quota_poll_timer.timeout.connect(self._maybe_update_from_local_quota)
        self._last_typeless_cfg_mtime: Optional[float] = None
        self._build_ui()
        self._load_saved_login_fields()

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)

        self.stack_login = QWidget()
        login_l = QVBoxLayout(self.stack_login)
        form = QFormLayout()
        self.phone_edit = QLineEdit()
        self.phone_edit.setPlaceholderText("11 位手机号")
        self.password_edit = QLineEdit()
        self.password_edit.setEchoMode(QLineEdit.Password)
        self.remember_cb = QCheckBox("记住密码")
        form.addRow("手机号", self.phone_edit)
        form.addRow("密码", self.password_edit)
        form.addRow("", self.remember_cb)
        login_l.addLayout(form)
        btn_row = QHBoxLayout()
        self.login_btn = QPushButton("登录")
        self.register_btn = QPushButton("注册")
        btn_row.addWidget(self.login_btn)
        btn_row.addWidget(self.register_btn)
        login_l.addLayout(btn_row)
        login_l.addStretch()

        self.stack_profile = QWidget()
        prof_l = QVBoxLayout(self.stack_profile)
        self.profile_header_label = QLabel("")
        self.profile_header_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.profile_header_label.setWordWrap(True)
        prof_l.addWidget(self.profile_header_label)

        self._quota_daily_w, self._bar_daily = _make_quota_block("每日")
        self._quota_weekly_w, self._bar_weekly = _make_quota_block("每周")
        self._quota_monthly_w, self._bar_monthly = _make_quota_block("每月")
        prof_l.addWidget(self._quota_daily_w)
        prof_l.addWidget(self._quota_weekly_w)
        prof_l.addWidget(self._quota_monthly_w)

        row = QHBoxLayout()
        self.refresh_btn = QPushButton("刷新")
        self.recharge_btn = QPushButton("微信充值")
        self.recharge_btn.setToolTip("跳转微信 Native 支付（由云托管服务端下单）")
        self.logout_btn = QPushButton("退出登录")
        row.addWidget(self.refresh_btn)
        row.addWidget(self.recharge_btn)
        row.addWidget(self.logout_btn)
        row.addStretch()
        prof_l.addLayout(row)

        redeem_row = QHBoxLayout()
        redeem_row.addWidget(QLabel("免费券兑换码"))
        self.coupon_code_edit = QLineEdit()
        self.coupon_code_edit.setPlaceholderText("例如 VK2M-ABCD-EFGH-JKLM")
        self.redeem_coupon_btn = QPushButton("兑换")
        redeem_row.addWidget(self.coupon_code_edit, 1)
        redeem_row.addWidget(self.redeem_coupon_btn)
        prof_l.addLayout(redeem_row)

        prof_l.addStretch()

        root.addWidget(self.stack_login)
        root.addWidget(self.stack_profile)
        self.stack_profile.hide()

        self.login_btn.clicked.connect(self._on_login)
        self.register_btn.clicked.connect(self._on_register)
        self.refresh_btn.clicked.connect(self._refresh_me)
        self.recharge_btn.clicked.connect(self._on_recharge_wechat)
        self.redeem_coupon_btn.clicked.connect(self._on_redeem_coupon)
        self.logout_btn.clicked.connect(self._on_logout)

        if cloud_settings.get_token():
            self.stack_login.hide()
            self.stack_profile.show()
        else:
            self.stack_profile.hide()
            self.stack_login.show()

    def showEvent(self, event):
        super().showEvent(event)
        if cloud_settings.get_token():
            self._show_profile_and_refresh()

    def _load_saved_login_fields(self):
        if cloud_settings.get_remember():
            self.remember_cb.setChecked(True)
            self.phone_edit.setText(cloud_settings.get_saved_phone())
            self.password_edit.setText(cloud_settings.get_saved_password())

    def _client(self) -> CloudApi:
        base = cloud_settings.effective_api_base()
        if not base:
            raise CloudApiError("未配置云端服务地址")
        return CloudApi(base, cloud_settings.get_token() or None)

    def _on_login(self):
        try:
            api = self._client()
            phone = self.phone_edit.text().strip()
            pw = self.password_edit.text()
            token = api.login(phone, pw)
            cloud_settings.set_token(token)
            if self.remember_cb.isChecked():
                cloud_settings.set_remember(True)
                cloud_settings.set_saved_phone(phone)
                cloud_settings.set_saved_password(pw)
            else:
                cloud_settings.set_remember(False)
                cloud_settings.set_saved_phone("")
                cloud_settings.set_saved_password("")
            self._sync_typeless_from_api()
            self._show_profile_and_refresh()
        except CloudApiError as e:
            QMessageBox.warning(self, "登录失败", str(e))
        except Exception as e:
            QMessageBox.warning(self, "登录失败", str(e))

    def _on_register(self):
        try:
            api = self._client()
            phone = self.phone_edit.text().strip()
            pw = self.password_edit.text()
            token = api.register(phone, pw)
            cloud_settings.set_token(token)
            if self.remember_cb.isChecked():
                cloud_settings.set_remember(True)
                cloud_settings.set_saved_phone(phone)
                cloud_settings.set_saved_password(pw)
            self._sync_typeless_from_api()
            self._show_profile_and_refresh()
        except CloudApiError as e:
            QMessageBox.warning(self, "注册失败", str(e))
        except Exception as e:
            QMessageBox.warning(self, "注册失败", str(e))

    def _on_logout(self):
        cloud_settings.clear_token()
        typeless_store.clear_session_keep_toggle()
        self._me = None
        self.stack_profile.hide()
        self.stack_login.show()
        self._quota_poll_timer.stop()
        self._last_typeless_cfg_mtime = None

    def _maybe_update_from_local_quota(self):
        if not self._me or not self.stack_profile.isVisible():
            return
        try:
            path = typeless_store.typeless_config_path()
            if not path.exists():
                return
            mtime = path.stat().st_mtime
            if self._last_typeless_cfg_mtime is not None and mtime <= self._last_typeless_cfg_mtime:
                return
            self._last_typeless_cfg_mtime = mtime

            cfg = typeless_store.load()
            used_daily = int(cfg.get("used_daily") or 0)
            used_weekly = int(cfg.get("used_weekly") or 0)
            used_monthly = int(cfg.get("used_monthly") or 0)
            limit_daily = int(cfg.get("limit_daily") or 0)
            limit_weekly = int(cfg.get("limit_weekly") or 0)
            limit_monthly = int(cfg.get("limit_monthly") or 0)
            token_valid_until = cfg.get("token_valid_until")

            changed = False
            if self._me.get("used_daily") != used_daily:
                self._me["used_daily"] = used_daily
                changed = True
            if self._me.get("used_weekly") != used_weekly:
                self._me["used_weekly"] = used_weekly
                changed = True
            if self._me.get("used_monthly") != used_monthly:
                self._me["used_monthly"] = used_monthly
                changed = True
            if self._me.get("limit_daily") != limit_daily:
                self._me["limit_daily"] = limit_daily
                changed = True
            if self._me.get("limit_weekly") != limit_weekly:
                self._me["limit_weekly"] = limit_weekly
                changed = True
            if self._me.get("limit_monthly") != limit_monthly:
                self._me["limit_monthly"] = limit_monthly
                changed = True
            if self._me.get("token_valid_until") != token_valid_until:
                self._me["token_valid_until"] = token_valid_until
                changed = True

            if changed:
                self._render_profile()
        except Exception:
            return

    def _sync_typeless_from_api(self):
        tok = cloud_settings.get_token() or ""
        typeless_store.patch_cloud_token(tok)

    def _show_native_qr_dialog(self, code_url: str) -> QDialog:
        try:
            import qrcode
        except Exception as e:
            QMessageBox.warning(
                self,
                "充值失败",
                "缺少依赖 qrcode，请先执行：pip install qrcode\n\n详情：{}".format(e),
            )
            return

        qr = qrcode.QRCode(box_size=10, border=2)
        qr.add_data(code_url)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white").convert("RGB")

        w, h = img.size
        raw = img.tobytes("raw", "RGB")
        qimg = QImage(raw, w, h, w * 3, QImage.Format_RGB888).copy()
        pix = QPixmap.fromImage(qimg)

        dlg = QDialog(self)
        dlg.setWindowTitle("微信扫码支付")
        layout = QVBoxLayout(dlg)

        tip = QLabel("请使用手机微信扫描二维码完成支付。")
        tip.setAlignment(Qt.AlignCenter)
        layout.addWidget(tip)

        qr_label = QLabel()
        qr_label.setAlignment(Qt.AlignCenter)
        qr_label.setPixmap(pix)
        layout.addWidget(qr_label)

        btns = QDialogButtonBox(QDialogButtonBox.Close)
        btns.rejected.connect(dlg.reject)
        layout.addWidget(btns)
        return dlg

    def _on_recharge_order_finished(self, cancel_event: object, status: str):
        # 只处理当前活跃的轮询（避免旧轮询结果把新对话关掉）
        if self._recharge_cancel_event is None or cancel_event is not self._recharge_cancel_event:
            return
        self._recharge_result = status
        dlg = self._recharge_dialog
        self._recharge_dialog = None
        if dlg is not None:
            # 先关闭二维码对话框，避免多模态弹窗遮挡影响体验。
            dlg.accept()
        if status == "paid":
            QMessageBox.information(self, "充值成功", "已成功充值。")
        elif status == "failed":
            QMessageBox.warning(self, "充值失败", "订单已标记为失败。")
        elif status == "timeout":
            QMessageBox.warning(self, "充值超时", "等待支付超时，请检查微信支付状态后再试。")
        else:
            QMessageBox.warning(self, "充值失败", "充值状态查询发生错误，请重试。")
        if self._recharge_cancel_event is not None:
            self._recharge_cancel_event.set()

    @staticmethod
    def _format_fen(fen: int) -> str:
        return "{:.2f}".format(max(0, int(fen)) / 100.0)

    def _pick_recharge_plan(self) -> Optional[str]:
        policy = (self._me or {}).get("policy") or {}
        prices = policy.get("recharge_prices_fen") or {}
        monthly = int(prices.get("monthly", 100))
        quarterly = int(prices.get("quarterly", 270))
        yearly = int(prices.get("yearly", 999))
        options = [
            "包月  {}元".format(self._format_fen(monthly)),
            "包季  {}元".format(self._format_fen(quarterly)),
            "包年  {}元".format(self._format_fen(yearly)),
        ]
        text, ok = QInputDialog.getItem(
            self,
            "选择充值套餐",
            "请选择套餐：",
            options,
            0,
            False,
        )
        if not ok:
            return None
        mapping = {
            options[0]: "monthly",
            options[1]: "quarterly",
            options[2]: "yearly",
        }
        return mapping.get(text)

    def _on_recharge_wechat(self):
        if not cloud_settings.get_token():
            QMessageBox.warning(self, "提示", "请先登录")
            return
        try:
            api = self._client()
            api.access_token = cloud_settings.get_token()
            plan = self._pick_recharge_plan()
            if not plan:
                return
            data = api.payment_wechat_native(plan=plan)
            code_url = data.get("code_url") or data.get("mweb_url")
            h5 = data.get("h5_url")
            if code_url:
                if self._recharge_dialog is not None:
                    QMessageBox.information(self, "提示", "已有充值对话框正在等待支付。")
                    return
                out_trade_no = (data.get("out_trade_no") or "").strip()
                if not out_trade_no:
                    QMessageBox.warning(
                        self,
                        "充值失败",
                        "服务端未返回 out_trade_no，无法轮询支付状态。\n原始数据：\n{}".format(
                            json.dumps(data, ensure_ascii=False, indent=2)
                        ),
                    )
                    return

                dlg = self._show_native_qr_dialog(code_url)
                self._recharge_dialog = dlg
                self._recharge_result = None

                cancel_event = threading.Event()
                self._recharge_cancel_event = cancel_event
                # 用户手动关闭：取消轮询
                dlg.finished.connect(lambda _: cancel_event.set())

                # 开始轮询订单状态
                api_base = cloud_settings.effective_api_base()
                tok = cloud_settings.get_token() or ""
                runnable = _RechargeOrderRunnable(
                    api_base=api_base,
                    token=tok,
                    out_trade_no=out_trade_no,
                    cancel_event=cancel_event,
                    signals=self._recharge_signals,
                )
                QThreadPool.globalInstance().start(runnable)

                dlg.exec()
            elif h5:
                QDesktopServices.openUrl(QUrl(h5))
            else:
                QMessageBox.information(
                    self,
                    "下单结果",
                    "服务端未返回可打开的支付链接，原始数据：\n{}".format(
                        json.dumps(data, ensure_ascii=False, indent=2)
                    ),
                )
            if self._recharge_result == "paid":
                self._refresh_me()
        except CloudApiError as e:
            QMessageBox.warning(self, "充值失败", str(e))
        except Exception as e:
            QMessageBox.warning(self, "充值失败", str(e))
        finally:
            # 清理当前轮询状态
            self._recharge_dialog = None
            self._recharge_cancel_event = None

    def _on_redeem_coupon(self):
        code = self.coupon_code_edit.text().strip()
        if not code:
            QMessageBox.warning(self, "兑换失败", "请输入兑换码")
            return
        try:
            api = self._client()
            api.access_token = cloud_settings.get_token()
            me = api.coupon_redeem(code)
            self._me = me
            typeless_store.patch_cloud_token(cloud_settings.get_token() or "")
            typeless_store.set_user_profile(self._me)
            self._render_profile()
            self.coupon_code_edit.clear()
            QMessageBox.information(self, "兑换成功", "免费券已生效，订阅有效期已延长。")
        except CloudApiError as e:
            QMessageBox.warning(self, "兑换失败", str(e))
        except Exception as e:
            QMessageBox.warning(self, "兑换失败", str(e))

    def _show_profile_and_refresh(self):
        self.stack_login.hide()
        self.stack_profile.show()
        self._quota_poll_timer.start()
        self._refresh_me()

    def _on_users_me_finished(
        self,
        me: Optional[Dict[str, Any]],
        err_msg: str,
        seq: int,
        status_code: int,
    ):
        if seq != self._refresh_seq:
            return
        if err_msg:
            if status_code == 401:
                cloud_settings.clear_token()
                typeless_store.clear_session_keep_toggle()
                self._me = None
                self.stack_profile.hide()
                self.stack_login.show()
            QMessageBox.warning(self, "刷新失败", err_msg)
            if self._me:
                self._render_profile()
            elif self.stack_profile.isVisible():
                self.profile_header_label.setText("无法加载用户信息。\n\n{}".format(err_msg))
            return
        self._me = me
        typeless_store.patch_cloud_token(cloud_settings.get_token() or "")
        typeless_store.set_user_profile(self._me)
        self._render_profile()

    def _refresh_me(self):
        if not cloud_settings.get_token():
            self._on_logout()
            return
        base = cloud_settings.effective_api_base()
        if not base:
            QMessageBox.warning(self, "刷新失败", "未配置云端服务地址")
            return
        self._refresh_seq += 1
        seq = self._refresh_seq
        self.profile_header_label.setText("用户信息正在加载中…")
        self._set_quota_rows_visible(False, False, False)
        tok = cloud_settings.get_token() or ""
        QThreadPool.globalInstance().start(
            _UsersMeRunnable(base, tok, self._users_me_signals, seq)
        )

    def _set_quota_rows_visible(self, d: bool, w: bool, m: bool) -> None:
        self._quota_daily_w.setVisible(d)
        self._quota_weekly_w.setVisible(w)
        self._quota_monthly_w.setVisible(m)

    def _render_profile(self):
        if not self._me:
            return
        m = self._me
        pol = m.get("policy") or {}
        show_d, show_w, show_m = _policy_quota_visibility(pol)
        self._set_quota_rows_visible(show_d, show_w, show_m)

        header_lines = [
            "手机号: {}".format(m.get("phone", "")),
            "Token 有效期: {}".format(m.get("token_valid_until") or "无"),
        ]
        self.profile_header_label.setText("\n".join(header_lines))

        if show_d:
            _apply_quota_progress(
                self._bar_daily,
                int(m.get("used_daily") or 0),
                int(m.get("limit_daily") or 0),
            )
        if show_w:
            _apply_quota_progress(
                self._bar_weekly,
                int(m.get("used_weekly") or 0),
                int(m.get("limit_weekly") or 0),
            )
        if show_m:
            _apply_quota_progress(
                self._bar_monthly,
                int(m.get("used_monthly") or 0),
                int(m.get("limit_monthly") or 0),
            )


