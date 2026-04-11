#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

try:
    import fcntl
except ImportError:  # pragma: no cover - Windows does not provide fcntl.
    fcntl = None


DEFAULT_POLICY = {
    "retrospective": {
        "thresholds": {
            "modified_files": {"supporting": 5, "strong": 8},
            "elapsed_minutes": {"supporting": 15, "strong": 30},
            "idle_gap_minutes": 10,
        },
        "health_digest": {
            "min_emit_spacing_seconds": 120,
        },
        "messages": {
            "session_start_guidance": "Open .copilot/workspace/operations/HEARTBEAT.md and run the Checks section. If the Stop hook later flags significant work, call the session_reflect MCP tool before stopping.",
            "explicit_system": "Heartbeat trigger detected. Run .copilot/workspace/operations/HEARTBEAT.md checks now.",
            "stop_reflect_instruction": "Significant session detected. Call the session_reflect MCP tool now, process its output silently, then stop normally. If the MCP tool is unavailable, briefly review: execution accuracy, scope completeness, and anything worth persisting to .copilot/workspace/identity/SOUL.md, .copilot/workspace/knowledge/MEMORY.md, and .copilot/workspace/knowledge/USER.md, then rerun session_reflect once the heartbeat MCP server is restored.",
            "accepted_reason": "The user requested a retrospective. Call the session_reflect MCP tool, process its output, persist insights, then stop normally.",
        },
    }
}


def load_policy(policy_path: Path) -> dict:
    if not policy_path.exists():
        return DEFAULT_POLICY
    try:
        loaded = json.loads(policy_path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            return loaded
    except Exception:
        pass
    return DEFAULT_POLICY


def default_state() -> dict:
    return {
        "schema_version": 1,
        "session_id": "unknown",
        "session_state": "pending",
        "retrospective_state": "idle",
        "last_trigger": "",
        "last_write_epoch": 0,
        "last_soft_trigger_epoch": 0,
        "last_compaction_epoch": 0,
        "last_explicit_epoch": 0,
        "session_start_epoch": 0,
        "session_start_git_count": 0,
        "task_window_start_epoch": 0,
        "last_raw_tool_epoch": 0,
        "active_work_seconds": 0,
        "copilot_edit_count": 0,
        "tool_call_counter": 0,
        "intent_phase": "quiet",
        "intent_phase_epoch": 0,
        "intent_phase_version": 1,
        "last_digest_key": "",
        "last_digest_epoch": 0,
        "digest_emit_count": 0,
        "overlay_sensitive_surface": False,
        "overlay_parity_required": False,
        "overlay_verification_expected": False,
        "overlay_decision_capture_needed": False,
        "overlay_retro_requested": False,
        "signal_edit_started": False,
        "signal_scope_supporting": False,
        "signal_scope_strong": False,
        "signal_work_supporting": False,
        "signal_work_strong": False,
        "signal_compaction_seen": False,
        "signal_idle_reset_seen": False,
        "signal_cross_cutting": False,
        "signal_scope_widening": False,
        "signal_reflection_likely": False,
        "route_candidate": "",
        "route_reason": "",
        "route_confidence": 0.0,
        "route_source": "",
        "route_emitted": False,
        "route_epoch": 0,
        "route_last_hint_epoch": 0,
        "route_emitted_agents": [],
        "route_signal_counts": {},
        "changed_path_families": [],
        "touched_files_sample": [],
        "unique_touched_file_count": 0,
        "prior_small_batches": False,
        "prior_explicitness": False,
        "prior_reversibility": False,
        "prior_baseline_sensitive": False,
        "prior_research_first": False,
        "prior_non_interruptive_ux": False,
    }


def load_state(state_path: Path) -> dict:
    state = default_state()
    with file_lock(state_path):
        if not state_path.exists():
            return state
        try:
            loaded = json.loads(state_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                state.update({key: loaded[key] for key in state.keys() if key in loaded})
        except Exception:
            pass
    return state


def lock_path(path: Path) -> Path:
    return path.parent / f"{path.name}.lock"


@contextmanager
def file_lock(path: Path):
    if fcntl is None:
        yield
        return
    target = lock_path(path)
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("a+", encoding="utf-8") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    except OSError:
        yield


def read_event_lines(events_path: Path) -> list[str]:
    lines: list[str] = []
    with file_lock(events_path):
        if not events_path.exists():
            return lines
        try:
            lines.extend(events_path.read_text(encoding="utf-8").splitlines())
        except Exception:
            return lines
    return lines


def atomic_write(path: Path, text: str) -> None:
    last_error = None
    with file_lock(path):
        for _attempt in range(2):
            path.parent.mkdir(parents=True, exist_ok=True)
            file_descriptor, tmp_name = tempfile.mkstemp(
                prefix=f".{path.name}.",
                suffix=".tmp",
                dir=path.parent,
            )
            tmp_path = Path(tmp_name)
            try:
                with os.fdopen(file_descriptor, "w", encoding="utf-8") as handle:
                    handle.write(text)
                os.replace(tmp_path, path)
                return
            except FileNotFoundError as exc:
                last_error = exc
                tmp_path.unlink(missing_ok=True)
            except Exception:
                tmp_path.unlink(missing_ok=True)
                raise
    if last_error is not None:
        raise last_error


def save_state(state: dict, workspace: Path, state_path: Path) -> None:
    if not workspace.exists():
        return
    atomic_write(state_path, json.dumps(state, indent=2, sort_keys=True) + "\n")


def iso_utc(epoch: int) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))


def append_event(
    events_path: Path,
    workspace: Path,
    now: int,
    trigger: str,
    detail: str = "",
    duration_s=None,
    session_id: str = "",
) -> None:
    if not workspace.exists():
        return
    event = {"ts": now, "ts_utc": iso_utc(now), "trigger": trigger}
    if detail:
        event["detail"] = detail
    if duration_s is not None:
        event["duration_s"] = duration_s
    if session_id:
        event["session_id"] = session_id
    payload = json.dumps(event, sort_keys=True) + "\n"
    events_path.parent.mkdir(parents=True, exist_ok=True)
    with file_lock(events_path):
        with events_path.open("a", encoding="utf-8") as handle:
            handle.write(payload)


def compute_session_medians(events_path: Path) -> str:
    durations = []
    try:
        for line in read_event_lines(events_path):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except Exception:
                continue
            if event.get("trigger") == "stop" and isinstance(event.get("duration_s"), (int, float)):
                durations.append(int(event["duration_s"]))
    except Exception:
        return ""
    if not durations:
        return ""
    sorted_durations = sorted(durations)
    count = len(sorted_durations)
    mid = count // 2
    median = sorted_durations[mid] if count % 2 else (sorted_durations[mid - 1] + sorted_durations[mid]) // 2
    mins = median // 60
    secs = median % 60
    label = f"~{mins}m" if mins >= 1 and secs < 30 else (f"~{mins + 1}m" if mins >= 1 else f"~{secs}s")
    return f"Typical session: {label} (median of {count})."


def prune_events(events_path: Path, keep: int = 100) -> None:
    if not events_path.exists():
        return
    try:
        lines = [line for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(lines) > keep:
            atomic_write(events_path, "\n".join(lines[-keep:]) + "\n")
    except Exception:
        return


def set_sentinel(sentinel_path: Path, workspace: Path, now: int, session_id: str, status: str) -> None:
    if not workspace.exists():
        return
    text = f"{session_id}|{iso_utc(now)}|{status}\n"
    atomic_write(sentinel_path, text)


def sentinel_is_complete(sentinel_path: Path) -> bool:
    with file_lock(sentinel_path):
        if not sentinel_path.exists():
            return False
        try:
            parts = sentinel_path.read_text(encoding="utf-8").strip().split("|")
            if len(parts) >= 3 and parts[2].strip() == "complete":
                return True
        except Exception:
            return False
    return False


def reflection_event_complete(events_path: Path, session_id: str, session_start_epoch: int) -> bool:
    lines = read_event_lines(events_path)
    if not lines:
        return False
    for line in reversed(lines):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except Exception:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("trigger") != "session_reflect" or event.get("detail") != "complete":
            continue
        event_session_id = str(event.get("session_id") or "")
        if event_session_id:
            return event_session_id == session_id
        event_ts = event.get("ts")
        if isinstance(event_ts, (int, float)) and session_start_epoch > 0:
            return int(event_ts) >= session_start_epoch
    return False


def heartbeat_fresh(heartbeat_path: Path, now: int, minutes: int) -> bool:
    if not heartbeat_path.exists():
        return False
    try:
        return now - int(heartbeat_path.stat().st_mtime) < (minutes * 60)
    except Exception:
        return False


def get_git_modified_file_count() -> int:
    try:
        proc = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return 0
    if proc.returncode != 0:
        return 0
    return len([line for line in proc.stdout.splitlines() if line.strip()])


def read_workspace_file(workspace: Path, name: str, limit: int = 4000) -> str:
    path = workspace / name
    if not path.exists():
        return ""
    try:
        return path.read_text(encoding="utf-8", errors="ignore")[:limit]
    except Exception:
        return ""


def load_session_priors(workspace: Path) -> dict:
    soul = read_workspace_file(workspace, "identity/SOUL.md").lower()
    user = read_workspace_file(workspace, "knowledge/USER.md").lower()
    return {
        "prior_small_batches": "small batches" in soul,
        "prior_explicitness": "explicit over implicit" in soul,
        "prior_reversibility": "reversibility" in soul,
        "prior_baseline_sensitive": "baselines" in soul,
        "prior_research_first": (
            "research and design confirmation" in user or "investigation preference" in user
        ),
        "prior_non_interruptive_ux": "dislikes disruptive" in user or "non-blocking" in user,
    }


def close_work_window(state: dict) -> dict:
    task_window_start = int(state.get("task_window_start_epoch") or 0)
    last_tool = int(state.get("last_raw_tool_epoch") or 0)
    if task_window_start > 0 and last_tool >= task_window_start:
        state["active_work_seconds"] = int(state.get("active_work_seconds") or 0) + max(0, last_tool - task_window_start)
        state["task_window_start_epoch"] = 0
    return state


def recommend_retrospective(state: dict, modified_thresholds: dict, elapsed_thresholds: dict) -> tuple[bool, str]:
    strong_signals = []
    supporting_signals = []
    strong_modified = int(modified_thresholds.get("strong") or 8)
    supporting_modified = int(modified_thresholds.get("supporting") or 5)
    strong_elapsed_minutes = int(elapsed_thresholds.get("strong") or 30)
    supporting_elapsed_minutes = int(elapsed_thresholds.get("supporting") or 15)

    touched_files = int(state.get("unique_touched_file_count") or 0)
    session_start_count = int(state.get("session_start_git_count") or 0)
    delta_files = max(0, get_git_modified_file_count() - session_start_count)
    edit_count = int(state.get("copilot_edit_count") or 0)
    effective_files = touched_files if touched_files > 0 else (delta_files if delta_files > 0 else edit_count)
    if effective_files == 0:
        return (False, "no file activity detected since session start")

    if touched_files > 0:
        file_label = "files touched in this session"
    elif delta_files > 0:
        file_label = "files changed since session start"
    else:
        file_label = "files edited in this session (previously committed)"
    if effective_files >= strong_modified:
        strong_signals.append(f"{effective_files} {file_label}")
    elif effective_files >= supporting_modified:
        supporting_signals.append(f"{effective_files} {file_label}")

    active_minutes = int(state.get("active_work_seconds") or 0) // 60
    if active_minutes >= strong_elapsed_minutes:
        strong_signals.append(f"{active_minutes}m active work")
    elif active_minutes >= supporting_elapsed_minutes:
        supporting_signals.append(f"{active_minutes}m active work")

    start_epoch = int(state.get("session_start_epoch") or 0)
    if int(state.get("last_compaction_epoch") or 0) >= start_epoch > 0:
        supporting_signals.append("context compaction occurred")

    signals = strong_signals + supporting_signals
    return (bool(strong_signals) or len(supporting_signals) >= 2, ", ".join(signals))