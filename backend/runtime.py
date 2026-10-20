"""运行时调试与日志配置。"""

from __future__ import annotations

import logging
import os
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from pathlib import Path
from typing import Any, Iterable

import yaml

BACKEND_DEBUG_ENV_VAR = "NOVEL_GENERATOR_BACKEND_DEBUG"
BACKEND_PORT_ENV_VAR = "NOVEL_GENERATOR_BACKEND_PORT"
FRONTEND_PORT_ENV_VAR = "NOVEL_GENERATOR_FRONTEND_PORT"
PROFILE_ENV_VAR = "NOVEL_GENERATOR_PROFILE"
DEFAULT_BACKEND_HOST = "0.0.0.0"
DEFAULT_BACKEND_PORT = 9001
DEFAULT_FRONTEND_PORT = 9002
_TRUE_VALUES = {"1", "true", "yes", "on", "debug"}
_PROD_VALUES = {"prod", "production"}
_PROD_CONFIG_PATH = Path(__file__).resolve().parent / "config" / "config_prod.yaml"
_prod_config_cache: dict[str, Any] | None = None

# 每次绑定都创建新字典，异步请求和子任务不会修改彼此的日志上下文。
log_context: ContextVar[dict[str, str]] = ContextVar("log_context", default={})


@contextmanager
def bind_log_context(**fields: str) -> Iterator[None]:
    """在当前请求或步骤内补充日志关联信息，退出时恢复上层信息。

    Args:
        **fields: 请求、流程、节点或模型调用的标识。

    Yields:
        无；绑定在 with 语句内有效。
    """
    token = log_context.set({**log_context.get(), **fields})
    try:
        yield
    finally:
        log_context.reset(token)


class LogContextFilter(logging.Filter):
    """把当前异步请求的关联信息写入日志记录。"""

    def filter(self, record: logging.LogRecord) -> bool:
        """补充格式化器需要的上下文，保留所有日志。

        Args:
            record: 即将输出的日志记录。

        Returns:
            始终为 True。
        """
        record.context = " ".join(f"{key}={value}" for key, value in log_context.get().items())
        return True


def log_exception(
    target: logging.Logger,
    message: str,
    error: BaseException,
    *,
    level: int = logging.ERROR,
) -> None:
    """记录真实异常链；上层再次遇到同一错误时只记录失败位置。

    Args:
        target: 当前模块的 logger。
        message: 失败的操作及必要数据。
        error: 原始异常或保留了 cause 的业务异常。
        level: 日志级别，默认 ERROR。

    Returns:
        无。
    """
    current: BaseException | None = error
    while current is not None:
        if getattr(current, "_log_recorded", False):
            target.log(level, "%s type=%s error=%s", message, type(error).__name__, error, stacklevel=2)
            return
        current = current.__cause__ or current.__context__

    target.log(
        level, "%s type=%s error=%s", message, type(error).__name__, error,
        exc_info=(type(error), error, error.__traceback__),
        stack_info=error.__traceback__ is None, stacklevel=2,
    )
    error._log_recorded = True


def _is_truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in _TRUE_VALUES


def _get_port_from_env(env_name: str, default_port: int) -> int:
    raw_value = os.getenv(env_name)
    if raw_value is None or not raw_value.strip():
        return _validate_port(default_port, env_name)
    return _validate_port(raw_value.strip(), env_name)


def _validate_port(raw_value: object, label: str) -> int:
    try:
        port = int(str(raw_value).strip())
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} 必须是整数，当前值为 {raw_value!r}") from exc

    if not 1 <= port <= 65535:
        raise ValueError(f"{label} 必须位于 1 到 65535 之间，当前值为 {port}")
    return port


def use_prod_profile() -> bool:
    """当前进程是否按生产配置启动。"""
    return os.getenv(PROFILE_ENV_VAR, "").strip().lower() in _PROD_VALUES


def _load_prod_config() -> dict[str, Any]:
    """读取生产域名与端口配置。"""
    global _prod_config_cache
    if _prod_config_cache is not None:
        return _prod_config_cache
    if not _PROD_CONFIG_PATH.exists():
        raise FileNotFoundError(f"生产配置不存在：{_PROD_CONFIG_PATH}")
    with _PROD_CONFIG_PATH.open("r", encoding="utf-8") as file:
        data = yaml.safe_load(file) or {}
    if not isinstance(data, dict):
        raise ValueError(f"生产配置必须是映射：{_PROD_CONFIG_PATH}")
    _prod_config_cache = data
    return data


def get_bind_host() -> str:
    """进程监听地址。默认 0.0.0.0，生产配置可覆盖。"""
    if use_prod_profile():
        host = str(_load_prod_config().get("bind_host") or "").strip()
        if not host:
            raise ValueError("config_prod.yaml 缺少 bind_host")
        return host
    return DEFAULT_BACKEND_HOST


def get_public_host() -> str:
    """浏览器访问使用的主机名。优先读生产配置中的公网 IP。"""
    try:
        host = str(_load_prod_config().get("public_host") or "").strip()
        if host and host != "0.0.0.0":
            return host
    except (FileNotFoundError, ValueError, OSError):
        pass
    return "127.0.0.1"


def get_cors_hosts() -> list[str]:
    """CORS 允许的主机：本机 + 生产公网 IP。"""
    hosts = ["127.0.0.1", "localhost"]
    public_host = get_public_host()
    if public_host not in hosts:
        hosts.append(public_host)
    return hosts


def get_public_scheme() -> str:
    """对外访问协议。"""
    if not use_prod_profile():
        return "http"
    scheme = str(_load_prod_config().get("public_scheme") or "http").strip().lower()
    if scheme not in {"http", "https"}:
        raise ValueError(f"public_scheme 只能是 http 或 https，当前值为 {scheme!r}")
    return scheme


def _prod_port(key: str, fallback: int) -> int:
    if not use_prod_profile():
        return fallback
    if key not in _load_prod_config():
        raise ValueError(f"config_prod.yaml 缺少 {key}")
    return _validate_port(_load_prod_config()[key], key)


def get_backend_port() -> int:
    """读取并校验后端监听端口。

    Args:
        无。

    Returns:
        环境变量指定的有效 TCP 端口；未指定时，生产配置优先，否则返回项目默认端口。

    Raises:
        ValueError: 环境变量不是整数或超出有效端口范围。
    """
    if os.getenv(BACKEND_PORT_ENV_VAR, "").strip():
        return _get_port_from_env(BACKEND_PORT_ENV_VAR, DEFAULT_BACKEND_PORT)
    return _prod_port("backend_port", DEFAULT_BACKEND_PORT)


def get_frontend_port() -> int:
    """读取并校验前端监听端口。

    Args:
        无。

    Returns:
        环境变量指定的有效 TCP 端口；未指定时，生产配置优先，否则返回项目默认端口。

    Raises:
        ValueError: 环境变量不是整数或超出有效端口范围。
    """
    if os.getenv(FRONTEND_PORT_ENV_VAR, "").strip():
        return _get_port_from_env(FRONTEND_PORT_ENV_VAR, DEFAULT_FRONTEND_PORT)
    return _prod_port("frontend_port", DEFAULT_FRONTEND_PORT)


def format_origin(host: str, port: int, scheme: str | None = None) -> str:
    """拼对外地址。80/443 不带端口。"""
    resolved_scheme = scheme or get_public_scheme()
    if (resolved_scheme == "http" and port == 80) or (resolved_scheme == "https" and port == 443):
        return f"{resolved_scheme}://{host}"
    return f"{resolved_scheme}://{host}:{port}"


def get_frontend_origins() -> list[str]:
    """浏览器来源白名单：本机与生产公网 IP 均放行。"""
    port = get_frontend_port()
    return [format_origin(host, port) for host in get_cors_hosts()]


def apply_runtime_flags_from_argv(argv: Iterable[str] | None = None) -> bool:
    """根据命令行参数与环境变量解析后端调试开关。"""
    args = list(sys.argv[1:] if argv is None else argv)

    if "--debug" in args:
        enabled = True
    elif "--no-debug" in args:
        enabled = False
    else:
        enabled = _is_truthy(os.getenv(BACKEND_DEBUG_ENV_VAR))

    os.environ[BACKEND_DEBUG_ENV_VAR] = "1" if enabled else "0"
    return enabled


def is_backend_debug_enabled() -> bool:
    """返回当前后端是否启用调试模式。"""
    return _is_truthy(os.getenv(BACKEND_DEBUG_ENV_VAR))


def get_backend_log_level() -> str:
    """根据调试状态返回日志级别。"""
    return "DEBUG" if is_backend_debug_enabled() else "INFO"


def set_backend_debug_enabled(enabled: bool) -> None:
    """立即切换应用日志和 AI 原始内容的输出，不重建日志处理器。

    Args:
        enabled: 是否输出调试日志。

    Returns:
        无。
    """
    os.environ[BACKEND_DEBUG_ENV_VAR] = "1" if enabled else "0"
    for name in ("main", "backend", "llm"):
        logging.getLogger(name).setLevel(get_backend_log_level())
    logging.getLogger(__name__).info("调试日志已%s", "开启" if enabled else "关闭")


def build_uvicorn_log_config() -> dict[str, Any]:
    """生成适用于 uvicorn 的控制台日志配置。"""
    app_log_level = get_backend_log_level()
    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {
                "()": "uvicorn.logging.DefaultFormatter",
                "fmt": "%(asctime)s | %(levelprefix)s | %(name)s | %(filename)s:%(lineno)d | %(context)s | %(message)s",
                "datefmt": "%Y-%m-%d %H:%M:%S",
                "use_colors": False,
            },
            "access": {
                "()": "uvicorn.logging.AccessFormatter",
                "fmt": "%(asctime)s | %(levelprefix)s | %(client_addr)s - \"%(request_line)s\" %(status_code)s",
                "datefmt": "%Y-%m-%d %H:%M:%S",
                "use_colors": False,
            },
        },
        "filters": {
            "context": {"()": "backend.runtime.LogContextFilter"},
        },
        "handlers": {
            "default": {
                "class": "logging.StreamHandler",
                "formatter": "default",
                "stream": "ext://sys.stdout",
                "filters": ["context"],
            },
            "access": {
                "class": "logging.StreamHandler",
                "formatter": "access",
                "stream": "ext://sys.stdout",
            },
        },
        "root": {
            "handlers": ["default"],
            "level": "WARNING",
        },
        "loggers": {
            "main": {
                "handlers": ["default"],
                "level": app_log_level,
                "propagate": False,
            },
            "backend": {
                "handlers": ["default"],
                "level": app_log_level,
                "propagate": False,
            },
            "llm": {
                "handlers": ["default"],
                "level": app_log_level,
                "propagate": False,
            },
            "uvicorn": {
                "handlers": ["default"],
                "level": "INFO",
                "propagate": False,
            },
            "uvicorn.error": {
                "handlers": ["default"],
                "level": "INFO",
                "propagate": False,
            },
            "uvicorn.access": {
                "handlers": ["access"],
                "level": "INFO",
                "propagate": False,
            },
            "httpcore": {
                "level": "WARNING",
            },
            "httpx": {
                "level": "WARNING",
            },
            "openai": {
                "level": "WARNING",
            },
            "anthropic": {
                "level": "WARNING",
            },
            "google": {
                "level": "WARNING",
            },
            "pymongo": {
                "level": "WARNING",
            },
        },
    }
