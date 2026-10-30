from __future__ import annotations
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any
import hashlib, json, uuid

def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()

def stable_id(prefix: str, *parts: str) -> str:
    digest = hashlib.sha256("\n".join(parts).encode()).hexdigest()[:16]
    return f"{prefix}-{digest}"

@dataclass
class SourceRef:
    id: str
    kind: str
    title: str
    uri: str
    observed_at: str | None = None
    content_hash: str | None = None
    locator: str | None = None
    def to_dict(self) -> dict[str, Any]:
        return {"id": self.id, "kind": self.kind, "title": self.title, "uri": self.uri,
                "observedAt": self.observed_at, "contentHash": self.content_hash, "locator": self.locator}
    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> "SourceRef":
        return cls(str(value.get("id") or uuid.uuid4()), str(value.get("kind", "unknown")),
                   str(value.get("title", "未命名资料")), str(value.get("uri", "")),
                   value.get("observedAt"), value.get("contentHash"), value.get("locator"))

@dataclass
class Execution:
    state: str = "none"
    agent_id: str | None = None
    adapter: str | None = None
    summary: str | None = None
    evidence: list[str] = field(default_factory=list)
    updated_at: str = field(default_factory=now_iso)
    def to_dict(self):
        return {"state": self.state, "agentID": self.agent_id, "adapter": self.adapter,
                "summary": self.summary, "evidence": self.evidence, "updatedAt": self.updated_at}
    @classmethod
    def from_dict(cls, value):
        return cls(value.get("state", "none"), value.get("agentID"), value.get("adapter"),
                   value.get("summary"), list(value.get("evidence", [])), value.get("updatedAt", now_iso()))

@dataclass
class Task:
    id: str
    title: str
    priority: str = "mid"
    status: str = "backlog"
    tags: list[str] = field(default_factory=list)
    notes: str = ""
    order: int = 0
    created_at: str = field(default_factory=now_iso)
    done_at: str | None = None
    source_refs: list[SourceRef] = field(default_factory=list)
    execution: Execution | None = None
    def to_dict(self):
        out = {"id": self.id, "title": self.title, "priority": self.priority, "status": self.status,
               "tags": self.tags, "notes": self.notes, "order": self.order, "createdAt": self.created_at}
        if self.done_at: out["doneAt"] = self.done_at
        if self.source_refs: out["sourceRefs"] = [x.to_dict() for x in self.source_refs]
        if self.execution: out["execution"] = self.execution.to_dict()
        return out
    @classmethod
    def from_dict(cls, value):
        return cls(str(value.get("id") or uuid.uuid4()), str(value.get("title", "(无标题)")),
                   value.get("priority", "mid") if value.get("priority") in {"high", "mid", "low"} else "mid",
                   value.get("status", "backlog") if value.get("status") in {"backlog", "today", "doing", "done", "trash"} else "backlog",
                   list(value.get("tags", [])), str(value.get("notes", "")), int(value.get("order", 0)),
                   value.get("createdAt", now_iso()), value.get("doneAt"),
                   [SourceRef.from_dict(x) for x in value.get("sourceRefs", []) if isinstance(x, dict)],
                   Execution.from_dict(value["execution"]) if isinstance(value.get("execution"), dict) else None)

@dataclass
class Board:
    version: int = 1
    updated_at: str = field(default_factory=now_iso)
    day: str = field(default_factory=lambda: now_iso()[:10])
    tasks: list[Task] = field(default_factory=list)
    def to_dict(self):
        return {"version": self.version, "updatedAt": self.updated_at, "day": self.day,
                "tasks": [x.to_dict() for x in self.tasks]}
    @classmethod
    def from_dict(cls, value):
        return cls(int(value.get("version", 1)), value.get("updatedAt", now_iso()), value.get("day", now_iso()[:10]),
                   [Task.from_dict(x) for x in value.get("tasks", []) if isinstance(x, dict)])
