"""Optional direct Feishu collection; all remote operations are reads.

The cloud-agent handoff remains independent. This adapter uses the installed
CLI's own user authorization, never Trae's executable or token files. Coverage
is a claim about the requested interval, not a cursor: the caller persists it.
"""
from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
import html
import json
from pathlib import Path
import re
from urllib.parse import quote
from zoneinfo import ZoneInfo

from . import acquisition as auto

TZ = ZoneInfo("Asia/Shanghai")


class SourceError(RuntimeError):
    pass


def _meeting_datetime(value: object) -> datetime:
    """Normalize Feishu meeting timestamps from epoch or API display strings."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return datetime.fromtimestamp(value, TZ)
    if isinstance(value, str):
        raw = value.strip()
        if re.fullmatch(r"\d+(?:\.\d+)?", raw):
            return datetime.fromtimestamp(float(raw), TZ)
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            raise SourceError("invalid_meeting_time") from None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=TZ)
        return parsed.astimezone(TZ)
    raise SourceError("invalid_meeting_time")


def _reason(exc: Exception) -> str:
    # CLI errors can contain business text; only persist known error metadata.
    if hasattr(exc, "as_dict"):
        return json.dumps(exc.as_dict(), ensure_ascii=False)
    if isinstance(exc, SourceError):
        return str(exc)
    return type(exc).__name__


def _shortcut(client, args: list[str]) -> dict:
    """Reuse FeishuClient's sanitized transport, profile, and timeout."""
    payload = client._run([*args, "--as", "user", "--json"])
    if payload.get("identity") not in (None, "user"):
        raise SourceError("unexpected_non_user_identity")
    return client._data(payload)


def _pages(fetch) -> list[dict]:
    result, token, seen = [], None, set()
    while True:
        data = fetch(token)
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            raise SourceError("invalid_items_response")
        if not isinstance(data.get("has_more"), bool):
            raise SourceError("missing_pagination_completion")
        if not all(isinstance(item, dict) for item in data["items"]):
            raise SourceError("invalid_list_item")
        result.extend(data["items"])
        if not data["has_more"]:
            return result
        token = data.get("page_token")
        if not isinstance(token, str) or not token or token in seen:
            raise SourceError("pagination_did_not_advance")
        seen.add(token)


def _windows(start: datetime, end: datetime):
    # Both search APIs allow at most one month; instance_view allows <40 days.
    # Splitting, unlike clipping to a recent lookback, keeps old holes recoverable.
    while start < end:
        stop = min(start + timedelta(days=28), end)
        yield start, stop
        start = stop


def _minute_metadata(item: dict) -> dict:
    """Pure parser shared in behavior with feishu_bridge/pull_minutes.py.

    The search creation time is not a recording start time. Require the actual
    recording timestamp, as the existing bridge does, rather than guessing it.
    """
    token = item.get("token") or item.get("minute_token")
    if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", token):
        raise SourceError("invalid_minute_token")
    display = html.unescape(item.get("display_info", ""))
    info = item.get("meta_data") or {}
    description = html.unescape(info.get("description", ""))
    match = re.search(r"开始时间\s*[:：]\s*(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})",
                      description or display)
    if not match:
        raise SourceError("recording_start_time_missing")
    start = datetime(*map(int, match.groups()), tzinfo=TZ)
    title = re.sub(r"<[^>]*>", "", display.splitlines()[0] if display else "").strip()
    if not title:
        raise SourceError("recording_title_missing")
    duration = (description or display).split("时长:", 1)[-1].split("时长：", 1)[-1]
    seconds = sum(int(m.group(1)) * scale for pattern, scale in
                  ((r"(\d+)\s*小时", 3600), (r"(\d+)\s*分", 60), (r"(\d+)\s*秒", 1))
                  for m in re.finditer(pattern, duration))
    metadata = {"schemaVersion": 1, "source": "feishu-minutes",
                "sourceMeetingID": "minutes:" + token, "minuteToken": token,
                "title": title, "startAt": start.isoformat(), "contentKind": "transcript",
                "sourceURL": info.get("app_link")}
    if seconds:
        metadata["endAt"] = (start + timedelta(seconds=seconds)).isoformat()
    return metadata


def _download_path(value: str, root: Path, folder: Path) -> Path:
    if not isinstance(value, str) or not value:
        raise SourceError("transcript_not_ready")
    path = Path(value)
    path = (path if path.is_absolute() else root / path).resolve()
    try:
        path.relative_to(folder.resolve())
    except ValueError:
        raise SourceError("transcript_outside_download_directory") from None
    if not path.is_file() or not path.stat().st_size:
        raise SourceError("transcript_not_ready")
    return path


def _publish(client, metadata: dict, folder: Path, queue: Path) -> dict:
    root = Path(getattr(client, "root", queue.parent)).resolve()
    folder = folder.resolve()
    try:
        relative = "./" + folder.relative_to(root).as_posix()
    except ValueError:
        raise SourceError("download_directory_outside_workspace") from None
    folder.mkdir(parents=True, exist_ok=True)
    note_id = metadata.get("noteID")
    if note_id:
        if not isinstance(note_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", note_id):
            raise SourceError("invalid_note_id")
        response = _shortcut(client, ["note", "+detail", "--note-id", note_id])
        # Installed CLI returns data.note; earlier releases returned data flat.
        detail = response.get("note", response)
        if not isinstance(detail, dict) or detail.get("note_id", note_id) != note_id:
            raise SourceError("invalid_note_detail_response")
        display = detail.get("note_display_type")
        document = detail.get("verbatim_doc_token")
        if display == "unified":
            # The CLI paginates the complete unified transcript atomically.
            # A unified note can also contain a Docx token: do not use it.
            output = relative + "/unified_transcript.md"
            _shortcut(client, ["note", "+transcript", "--note-id", note_id,
                               "--output", output, "--overwrite"])
            transcript = _download_path(output, root, folder)
            transcript_source = "note-unified"
        elif display in ("normal", "unknown") and document:
            if not isinstance(document, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", document):
                raise SourceError("invalid_verbatim_doc_token")
            response = _shortcut(client, ["docs", "+fetch", "--doc", document,
                                         "--doc-format", "markdown"])
            doc = response.get("document") or {}
            content = doc.get("content")
            if not isinstance(content, str) or not content.strip():
                raise SourceError("transcript_not_ready")
            # Retain the original full content and reference sidecar together.
            auto.save(folder / "verbatim-document.json", doc)
            transcript = folder / "transcript.md"
            transcript.write_text(content, encoding="utf-8")
            metadata = {**metadata, "verbatimDocToken": document}
            transcript_source = "note-docx"
        else:
            # An AI summary alone is never substituted for the raw transcript.
            raise SourceError("note_transcript_pending_or_unclassified")
    else:
        token = metadata["minuteToken"]
        data = _shortcut(client, ["minutes", "+detail", "--minute-tokens", token,
                                  "--transcript", "--overwrite", "--output-dir", relative])
        details = data.get("minutes")
        if not isinstance(details, list):
            raise SourceError("invalid_minutes_detail_response")
        detail = next((d for d in details if isinstance(d, dict) and d.get("minute_token") == token), None)
        if detail is None:
            raise SourceError("missing_matching_minute_detail")
        transcript = _download_path((detail.get("artifacts") or {}).get("transcript_file"), root, folder)
        note_id = detail.get("note_id")
        if detail.get("title"):
            metadata = {**metadata, "title": detail["title"]}
        transcript_source = "minutes"
    metadata = {**metadata, "transcriptPath": str(transcript),
                "originalSourcePath": str(transcript), "noteID": note_id,
                "transcriptSource": transcript_source,
                "contentSHA256": hashlib.sha256(transcript.read_bytes()).hexdigest()}
    path = folder / "meeting.json"
    auto.save(path, metadata)
    queued = auto.enqueue(path, runtime=queue)
    return {**queued, "sourceMeetingID": metadata["sourceMeetingID"],
            "title": metadata["title"], "startAt": metadata["startAt"],
            "meetingPath": str(path), "transcriptPath": str(transcript),
            "transcriptSource": transcript_source, "contentSHA256": metadata["contentSHA256"],
            "sourceURL": metadata.get("sourceURL")}


def _known_minutes(root: Path, start: datetime, end: datetime) -> list[dict]:
    """Use explicit IDs from existing records, never guess IDs or join by title."""
    known = {}
    for path in sorted((root / ".meeting-autopilot/jobs").glob("*/meeting.json")):
        try:
            item = json.loads(path.read_text(encoding="utf-8"))
            token = item.get("minuteToken")
            observed = datetime.fromisoformat(item["startAt"])
            if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", token):
                continue
            if observed.tzinfo is None or not start <= observed < end:
                continue
            if not isinstance(item.get("title"), str) or not item["title"].strip():
                continue
            metadata = {k: item[k] for k in ("schemaVersion", "sourceMeetingID", "minuteToken",
                        "title", "startAt", "endAt", "sourceURL") if k in item}
            metadata.setdefault("sourceMeetingID", "minutes:" + token)
            metadata.update(source="feishu-minutes", contentKind="transcript",
                            metadataOrigin="existing-local-meeting-record")
            known[token] = metadata
        except (OSError, ValueError, TypeError, KeyError):
            continue
    return list(known.values())


def collect(root: Path, runtime: Path, client, start: datetime, end: datetime, *, domains=None) -> dict:
    """Collect an exact interval without authenticating, granting, or messaging.

    Queuing is local and idempotent via meeting_autopilot. Missing permissions,
    incomplete pages, and unavailable transcripts never produce success coverage.
    """
    if start.tzinfo is None or end.tzinfo is None or start >= end:
        raise ValueError("ordered timezone-aware start/end required")
    root, runtime = Path(root), Path(runtime)
    domains = ("calendar", "meetings", "minutes") if domains is None else tuple(domains)
    if not domains or set(domains) - {"calendar", "meetings", "minutes"}:
        raise ValueError("unsupported collection domains")
    result = {"coverage": [], "meetings": [], "agenda": [], "blocked": [],
              "itemStates": [], "discoveredMeetings": []}
    queue = root / ".meeting-autopilot"
    seen_minutes = set()
    published = {}

    def coverage(source, first, last, state, reason=None):
        entry = {"source": source, "start": first.isoformat(), "end": last.isoformat(),
                 "state": state, "reason": reason}
        result["coverage"].append(entry)
        if state != "success":
            result["blocked"].append(entry.copy())

    for first, last in _windows(start, end):
        if "calendar" in domains:
            try:
                primary = _shortcut(client, ["calendar", "calendars", "primary"])
                calendars = primary.get("calendars")
                if not isinstance(calendars, list) or len(calendars) != 1:
                    raise SourceError("personal_primary_calendar_not_resolved")
                calendar_id = (calendars[0].get("calendar") or {}).get("calendar_id")
                if not isinstance(calendar_id, str) or not calendar_id:
                    raise SourceError("personal_primary_calendar_not_resolved")
                data = client.request("GET", "/open-apis/calendar/v4/calendars/" +
                                      quote(calendar_id, safe="") + "/events/instance_view",
                                      identity="user", params={"start_time": str(int(first.timestamp())),
                                                               "end_time": str(int(last.timestamp()))})
                # This endpoint's documented schema is unpaginated, unlike searches.
                if not isinstance(data.get("items"), list) or data.get("has_more"):
                    raise SourceError("incomplete_calendar_response")
                for item in data["items"]:
                    if not isinstance(item, dict) or not item.get("event_id"):
                        raise SourceError("invalid_calendar_event")
                    if item.get("status") == "cancelled" or item.get("self_rsvp_status") == "removed":
                        continue
                    result["agenda"].append({"eventID": item["event_id"], "title": item.get("summary", ""),
                                             "start": item.get("start_time"), "end": item.get("end_time"),
                                             "sourceURL": item.get("app_link"),
                                             "rsvp": item.get("self_rsvp_status")})
                    for name in ("recurrence", "rrule"):
                        if name in item:
                            result["agenda"][-1][name] = item[name]
                coverage("calendar", first, last, "success")
            except Exception as exc:
                coverage("calendar", first, last, "blocked", _reason(exc))

        for source in ("meetings", "minutes"):
            if source not in domains:
                continue
            try:
                base = ["--start", first.isoformat(), "--end", last.isoformat(), "--page-size", "30"]
                if source == "meetings":
                    owner = getattr(client, "config", {}).get("ownerOpenID")
                    if not owner:
                        owner = client.status().get("ownerOpenID")
                    if not isinstance(owner, str) or not re.fullmatch(r"ou_[A-Za-z0-9_]+", owner):
                        raise SourceError("personal_meeting_owner_not_resolved")
                    queries = [["vc", "+search", "--participant-ids", owner, *base],
                               ["vc", "+search", "--organizer-ids", owner, *base]]
                else:
                    queries = [["minutes", "+search", selector, "me", *base]
                               for selector in ("--owner-ids", "--participant-ids")]
                items = []
                for args in queries:
                    items.extend(_pages(lambda token, args=args: _shortcut(
                        client, args + (["--page-token", token] if token else []))))
                if source == "meetings":
                    for item in items:
                        display = html.unescape(item.get("display_info") or item.get("topic") or "")
                        result["discoveredMeetings"].append({
                            "meetingID": item.get("meeting_id") or item.get("id"),
                            "displayInfo": display,
                            "sourceURL": (item.get("meta_data") or {}).get("app_link"),
                            "materialState": "not_yet_verified"})
                failures, local_seen = [], set()
                for item in items:
                    item_id = item.get("meeting_id") or item.get("id") or item.get("token") or item.get("minute_token")
                    try:
                        if source == "meetings":
                            meeting_id = item.get("meeting_id") or item.get("id")
                            if not isinstance(meeting_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", meeting_id):
                                raise SourceError("invalid_meeting_id")
                            if meeting_id in local_seen:
                                continue
                            local_seen.add(meeting_id)
                            data = _shortcut(client, ["vc", "+detail", "--meeting-ids", meeting_id])
                            details = data.get("meetings")
                            if not isinstance(details, list):
                                raise SourceError("invalid_meeting_detail_response")
                            detail = next((d for d in details if d.get("meeting_id") == meeting_id), None)
                            if not detail:
                                raise SourceError("meeting_detail_missing")
                            token = detail.get("minute_token")
                            note_id = detail.get("note_id")
                            if not token and not note_id:
                                raise SourceError("meeting_transcript_pending")
                            if token and (not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", token)):
                                raise SourceError("invalid_minute_token")
                            value = detail.get("start_time") or item.get("start_time")
                            start_at = _meeting_datetime(value)
                            metadata = {"schemaVersion": 1, "source": "feishu-vc",
                                        "sourceMeetingID": meeting_id, "noteID": note_id,
                                        "title": detail.get("topic") or item.get("topic"),
                                        "startAt": start_at.isoformat(), "contentKind": "transcript"}
                            if token:
                                metadata["minuteToken"] = token
                            if detail.get("end_time"):
                                ended = _meeting_datetime(detail["end_time"])
                                if ended > end or ended < start_at:
                                    raise SourceError("meeting_not_ended_in_requested_interval")
                                metadata["endAt"] = ended.isoformat()
                            if not metadata["title"]:
                                raise SourceError("meeting_title_missing")
                        else:
                            metadata = _minute_metadata(item)
                            token = metadata["minuteToken"]
                        identity = metadata.get("minuteToken") or "note:" + str(metadata["noteID"])
                        if identity in seen_minutes:
                            if identity not in published:
                                raise SourceError("transcript_pending_in_other_source")
                            continue
                        seen_minutes.add(identity)
                        key = hashlib.sha256(identity.encode()).hexdigest()
                        folder = runtime / "sources" / key
                        queued = _publish(client, metadata, folder, queue)
                        published[identity] = queued
                        result["meetings"].append(queued)
                        result["itemStates"].append({"source": source, "sourceID": item_id,
                                                     "state": queued["state"], "jobID": queued["jobID"]})
                    except Exception as exc:
                        failures.append(_reason(exc))
                        result["itemStates"].append({"source": source, "sourceID": item_id,
                                                     "state": "pending", "reason": _reason(exc)})
                coverage(source, first, last, "pending" if failures else "success",
                         "; ".join(sorted(set(failures))) if failures else None)
            except Exception as exc:
                coverage(source, first, last, "blocked", _reason(exc))
                if source == "minutes" and getattr(exc, "kind", None) == "authorization":
                    # Permission to search and permission to read known files
                    # are separate. Refresh explicit, previously recorded IDs
                    # using the normal authorized read command. This does NOT
                    # fill a discovery/coverage gap or switch identities.
                    for metadata in _known_minutes(root, first, last):
                        token = metadata["minuteToken"]
                        if token in published:
                            continue
                        try:
                            folder = runtime / "sources" / hashlib.sha256(token.encode()).hexdigest()
                            queued = _publish(client, metadata, folder, queue)
                            published[token] = queued
                            result["meetings"].append(queued)
                            result["itemStates"].append({"source": "known-minutes", "sourceID": token,
                                                         "state": queued["state"], "jobID": queued["jobID"]})
                        except Exception as read_error:
                            result["itemStates"].append({"source": "known-minutes", "sourceID": token,
                                                         "state": "pending", "reason": _reason(read_error)})
    result["agenda"] = list({event["eventID"]: event for event in result["agenda"]}.values())
    result["discoveredMeetings"] = list({item["meetingID"]: item for item in result["discoveredMeetings"]
                                          if item["meetingID"]}.values())
    return result
