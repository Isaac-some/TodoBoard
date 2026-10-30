"""Bounded Feishu access through the existing CLI; no token files are read.

No listener or scheduled chat scan is started by this module. Event filtering and
instruction parsing are pure functions. Callers own the durable delivery ledger:
Feishu's idempotency window is only one hour, so an uncertain send must not be
blindly replayed later.
"""
from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from typing import Any, Iterable, Mapping


class FeishuError(RuntimeError):
    """A sanitized failure safe to persist; never includes raw CLI output."""

    def __init__(self, kind: str, *, code: Any = None,
                 missing_scopes: Iterable[str] = (), ambiguous: bool = False):
        self.kind = kind
        self.code = code if isinstance(code, (str, int)) else None
        self.missing_scopes = list(missing_scopes)
        self.ambiguous = ambiguous
        super().__init__(f"Feishu {kind}" + (f" ({self.code})" if self.code is not None else ""))

    def as_dict(self) -> dict:
        return {"kind": self.kind, "code": self.code,
                "missingScopes": self.missing_scopes, "ambiguous": self.ambiguous}


def _scopes(value: Any) -> list[str]:
    if isinstance(value, str):
        value = re.split(r"[\s,]+", value)
    if not isinstance(value, list):
        return []
    return sorted({v for v in value if isinstance(v, str) and re.fullmatch(r"[\w:.-]+", v)})


class FeishuClient:
    def __init__(self, root: Path, config: dict):
        self.root = Path(root)
        self.config = config.get("feishu", config)
        self.cli = self.config.get("cliPath", "lark-cli")
        self.profile = self.config.get("profile")
        self.timeout = min(120, max(1, int(self.config.get("timeoutSeconds", 45))))

    def _run(self, args: list[str], *, writing: bool = False,
             stdin: str | None = None) -> dict:
        argv = [self.cli, *args]
        if self.profile:
            argv.extend(["--profile", str(self.profile)])
        env = {**os.environ, "LARKSUITE_CLI_NO_UPDATE_NOTIFIER": "1",
               "LARKSUITE_CLI_NO_SKILLS_NOTIFIER": "1"}
        try:
            result = subprocess.run(argv, cwd=self.root, input=stdin, text=True,
                                    capture_output=True, timeout=self.timeout, env=env,
                                    check=False)
        except subprocess.TimeoutExpired:
            raise FeishuError("timeout", ambiguous=writing) from None
        except OSError:
            raise FeishuError("cli_unavailable") from None
        raw = result.stdout if result.returncode == 0 else result.stderr
        try:
            payload = json.loads(raw)
        except (ValueError, TypeError):
            raise FeishuError("invalid_response", ambiguous=writing) from None
        if not isinstance(payload, dict):
            raise FeishuError("invalid_response", ambiguous=writing)
        if result.returncode != 0 or payload.get("ok") is False:
            error = payload.get("error", {})
            error = error if isinstance(error, dict) else {}
            raw_kind = error.get("type", "request_failed")
            kind = raw_kind if raw_kind in {"authorization", "authentication", "validation",
                                           "confirmation", "network", "rate_limit"} else "request_failed"
            # A definite API refusal is known not to have sent. Transport/server
            # errors may arrive after the remote write, and require reconciliation.
            code = error.get("code")
            ambiguous = writing and kind not in {"authorization", "authentication",
                                                 "validation", "confirmation", "rate_limit"}
            raise FeishuError(kind, code=code,
                              missing_scopes=_scopes(error.get("missing_scopes", [])),
                              ambiguous=ambiguous)
        return payload

    @staticmethod
    def _data(payload: dict, *, writing: bool = False) -> dict:
        if payload.get("ok") is not True:
            raise FeishuError("invalid_response", ambiguous=writing)
        data = payload.get("data")
        if not isinstance(data, dict):
            raise FeishuError("invalid_response", ambiguous=writing)
        # Raw API envelopes may contain the upstream response inside data.
        if "code" in data and "data" in data:
            if data["code"] != 0:
                raise FeishuError("request_failed", code=data["code"], ambiguous=writing)
            data = data["data"]
        if not isinstance(data, dict):
            raise FeishuError("invalid_response", ambiguous=writing)
        return data

    def status(self) -> dict:
        raw = self._run(["auth", "status", "--json"])
        data = raw.get("data", raw)
        identities = data.get("identities", {}) if isinstance(data, dict) else {}
        user = identities.get("user", {}) or {}
        bot = identities.get("bot", {}) or {}
        return {
            "ownerOpenID": user.get("openId") or self.config.get("ownerOpenID"),
            "userScopes": _scopes(user.get("scope", user.get("scopes", []))),
            "userStatus": user.get("status", "unknown"),
            "userTokenStatus": user.get("tokenStatus", "unknown"),
            "appID": data.get("appId"),
            "bot": {key: bot[key] for key in ("status", "appName", "openId") if key in bot},
        }

    def request(self, method: str, path: str, *, identity: str = "user",
                params: dict | None = None, body: dict | None = None) -> dict:
        method = method.upper()
        if method not in {"GET", "POST", "PUT", "PATCH", "DELETE"}:
            raise ValueError("unsupported HTTP method")
        if identity not in {"user", "bot"}:
            raise ValueError("identity must be user or bot")
        if not path.startswith("/open-apis/") or "?" in path or "#" in path:
            raise ValueError("request path must be a plain /open-apis/ path")
        args = ["api", method, path, "--as", identity, "--json"]
        if params is not None:
            args += ["--params", json.dumps(params, ensure_ascii=False)]
        stdin = None
        if body is not None:
            args += ["--data", "-"]
            stdin = json.dumps(body, ensure_ascii=False)
        writing = method != "GET"
        return self._data(self._run(args, writing=writing, stdin=stdin), writing=writing)

