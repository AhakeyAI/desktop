import os
import queue
import sys
import time
from multiprocessing import Manager, Process

from util.common.lifecycle import lifecycle
from util.server.server_check_model import check_model
from util.server.server_cosmic import Cosmic, console
from util.server.server_init_recognizer import init_recognizer
from util.server.state import get_state

from . import logger


READY_SIGNAL_TIMEOUT_SECONDS = float(os.environ.get("CAPSWRITER_READY_TIMEOUT", "15"))
READY_SIGNAL_POLL_SECONDS = 0.2


def start_recognizer_process():
    """Start recognizer subprocess and wait for its ready signal with a fallback timeout."""

    check_model()

    state = get_state()
    Cosmic.sockets_id = Manager().list()
    stdin_fn = sys.stdin.fileno()
    recognize_process = Process(
        target=init_recognizer,
        args=(
            Cosmic.queue_in,
            Cosmic.queue_out,
            Cosmic.sockets_id,
            stdin_fn,
        ),
        daemon=False,
    )
    recognize_process.start()
    state.recognize_process = recognize_process
    logger.info("识别子进程已启动")

    # In frozen Windows builds the ready token occasionally never reaches the parent
    # even though the recognizer child is alive and has finished loading models.
    # Continue after a bounded wait instead of hanging the whole voice stack forever.
    import errno

    ready_deadline = time.monotonic() + READY_SIGNAL_TIMEOUT_SECONDS
    ready_received = False

    while not lifecycle.is_shutting_down:
        try:
            Cosmic.queue_out.get(timeout=READY_SIGNAL_POLL_SECONDS)
            ready_received = True
            break
        except queue.Empty:
            if not recognize_process.is_alive():
                break
            if time.monotonic() < ready_deadline:
                continue
            logger.warning(
                "等待识别子进程就绪信号超时（%.1fs），但子进程仍存活；继续启动 WebSocket 服务",
                READY_SIGNAL_TIMEOUT_SECONDS,
            )
            break
        except (InterruptedError, OSError) as exc:
            if isinstance(exc, InterruptedError) or getattr(exc, "errno", None) == errno.EINTR:
                continue
            raise

    if not recognize_process.is_alive():
        logger.error("识别子进程意外退出，可能是模型加载失败或运行环境异常")
        if recognize_process.exitcode not in (None, 0):
            logger.error(f"子进程退出码: {recognize_process.exitcode}")
        lifecycle.request_shutdown()

    if lifecycle.is_shutting_down:
        logger.warning("加载模型期间收到退出请求")
        if recognize_process.is_alive():
            recognize_process.terminate()
        return recognize_process

    if ready_received:
        logger.info("识别子进程已发送就绪信号")
    else:
        logger.warning("未收到就绪信号，按超时兜底继续启动服务")

    logger.info("模型加载完成，开始服务")
    console.rule("[green3]开始服务")
    console.line()
    return recognize_process
