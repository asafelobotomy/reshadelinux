#!/usr/bin/env python3
from __future__ import annotations

from pulse_paths import extract_tool_paths, path_requires_parity, update_touched_files
from pulse_state import get_git_modified_file_count


PHASE_ORDER = ("quiet", "orienting", "focused", "widening", "consolidating", "reflective")
SENSITIVE_FAMILIES = {"manifest", "config", "hook", "agent", "memory", "ci_release"}
VERIFICATION_FAMILIES = {"runtime", "hook", "config", "manifest", "ci_release"}


def get_activity_metrics(state: dict) -> dict:
    baseline = int(state.get("session_start_git_count") or 0)
    delta_files = max(0, get_git_modified_file_count() - baseline)
    edit_count = int(state.get("copilot_edit_count") or 0)
    touched_count = int(state.get("unique_touched_file_count") or 0)
    active_seconds = int(state.get("active_work_seconds") or 0)
    task_window_start = int(state.get("task_window_start_epoch") or 0)
    last_tool = int(state.get("last_raw_tool_epoch") or 0)
    if task_window_start > 0 and last_tool >= task_window_start:
        active_seconds += max(0, last_tool - task_window_start)
    return {
        "delta_files": delta_files,
        "edit_count": edit_count,
        "touched_count": touched_count,
        "effective_files": max(delta_files, edit_count, touched_count),
        "active_seconds": active_seconds,
        "active_minutes": active_seconds // 60,
    }


def compute_signal_snapshot(
    state: dict,
    modified_thresholds: dict,
    elapsed_thresholds: dict,
    recommend_retrospective_fn,
) -> dict:
    metrics = get_activity_metrics(state)
    strong_modified = int(modified_thresholds.get("strong") or 8)
    supporting_modified = int(modified_thresholds.get("supporting") or 5)
    strong_elapsed_minutes = int(elapsed_thresholds.get("strong") or 30)
    supporting_elapsed_minutes = int(elapsed_thresholds.get("supporting") or 15)
    start_epoch = int(state.get("session_start_epoch") or 0)
    compaction_seen = int(state.get("last_compaction_epoch") or 0) >= start_epoch > 0
    reflection_likely, _basis = recommend_retrospective_fn(state)
    families = list(state.get("changed_path_families") or [])
    return {
        "tool_activity": int(state.get("tool_call_counter") or 0) > 0,
        "edit_started": metrics["effective_files"] > 0,
        "scope_supporting": supporting_modified <= metrics["effective_files"] < strong_modified,
        "scope_strong": metrics["effective_files"] >= strong_modified,
        "work_supporting": supporting_elapsed_minutes <= metrics["active_minutes"] < strong_elapsed_minutes,
        "work_strong": metrics["active_minutes"] >= strong_elapsed_minutes,
        "compaction_seen": compaction_seen,
        "idle_reset_seen": bool(state.get("signal_idle_reset_seen")),
        "cross_cutting": len(families) >= 3,
        "scope_widening": metrics["effective_files"] >= 3 or len(families) >= 2,
        "reflection_likely": reflection_likely,
        **metrics,
    }


def compute_overlays(state: dict, signals: dict) -> dict:
    families = set(state.get("changed_path_families") or [])
    paths = list(state.get("touched_files_sample") or [])
    return {
        "overlay_sensitive_surface": bool(families.intersection(SENSITIVE_FAMILIES)),
        "overlay_parity_required": any(path_requires_parity(path_text) for path_text in paths),
        "overlay_verification_expected": bool(families.intersection(VERIFICATION_FAMILIES)),
        "overlay_decision_capture_needed": bool(signals["compaction_seen"] or signals["cross_cutting"]),
        "overlay_retro_requested": str(state.get("retrospective_state") or "idle") == "accepted",
    }


def advance_phase(state: dict, signals: dict, overlays: dict) -> str:
    phase = str(state.get("intent_phase") or "quiet")
    if phase not in PHASE_ORDER:
        phase = "quiet"
    while True:
        new_phase = phase
        if overlays["overlay_retro_requested"] or signals["reflection_likely"]:
            new_phase = "reflective"
        elif phase == "quiet":
            if signals["edit_started"] or signals["scope_supporting"] or signals["scope_strong"]:
                new_phase = "focused"
            elif signals["tool_activity"]:
                new_phase = "orienting"
        elif phase == "orienting":
            if signals["edit_started"]:
                new_phase = "focused"
        elif phase == "focused":
            if signals["scope_widening"]:
                new_phase = "widening"
        elif phase == "widening":
            if (
                signals["scope_supporting"]
                or signals["work_supporting"]
                or signals["work_strong"]
                or overlays["overlay_verification_expected"]
                or overlays["overlay_decision_capture_needed"]
                or overlays["overlay_sensitive_surface"]
            ):
                new_phase = "consolidating"
        if new_phase == phase:
            return phase
        phase = new_phase


def scope_evidence_text(signals: dict) -> str:
    active_minutes = int(signals.get("active_minutes") or 0)
    delta_files = int(signals.get("delta_files") or 0)
    touched_count = int(signals.get("touched_count") or 0)
    edit_count = int(signals.get("edit_count") or 0)
    if delta_files > 0:
        scope = f"{delta_files} files changed"
    elif touched_count > 0:
        scope = f"{touched_count} files touched"
    else:
        scope = f"{edit_count} edits tracked"
    parts = [f"{active_minutes}m active", scope]
    if signals.get("compaction_seen"):
        parts.append("compaction seen")
    return ", ".join(parts)


def build_digest_intent(phase: str, overlays: dict, signals: dict) -> tuple[str, str]:
    if overlays["overlay_retro_requested"]:
        return ("retrospective requested", "Prepare reflective closure before stopping")
    if phase == "reflective":
        return (
            "reflection likely at stop",
            f"Significant session signals are active ({scope_evidence_text(signals)})",
        )
    if overlays["overlay_parity_required"]:
        return ("preserve parity", "Mirrored surfaces are now active")
    if overlays["overlay_verification_expected"]:
        return ("tests and validation likely next", "Validation-sensitive work is accumulating")
    if overlays["overlay_decision_capture_needed"]:
        return ("capture decisions before loss", "Context compaction or broad work increases loss risk")
    if overlays["overlay_sensitive_surface"]:
        return ("verify baseline soon", "Sensitive behavior or policy surfaces changed")
    if phase == "consolidating":
        return ("verify baseline soon", f"Broader work is accumulating ({scope_evidence_text(signals)})")
    if phase == "widening":
        return ("capture decision", "Scope widened across multiple surfaces")
    if phase == "focused":
        return ("keep scope tight", "Narrow implementation work started")
    if phase == "orienting":
        return ("stay deliberate", "Session context is forming; no meaningful file changes yet")
    return ("", "")


def active_overlay_names(overlays: dict):
    return [key.replace("overlay_", "") for key, value in overlays.items() if value]


def build_digest_key(phase: str, overlays: dict, intent: str) -> str:
    if not intent:
        return ""
    return f"{phase}|{intent}|{','.join(sorted(active_overlay_names(overlays)))}"


def should_emit_digest(
    state: dict,
    phase: str,
    digest_key: str,
    phase_changed: bool,
    overlay_activated: bool,
    now: int,
    digest_min_spacing_seconds: int,
) -> bool:
    if not digest_key or phase in {"quiet", "orienting"}:
        return False
    if digest_key == str(state.get("last_digest_key") or ""):
        return False
    if phase == "focused" and bool(state.get("prior_non_interruptive_ux")) and not overlay_activated:
        return False
    last_digest_epoch = int(state.get("last_digest_epoch") or 0)
    if (
        last_digest_epoch > 0
        and digest_min_spacing_seconds > 0
        and (now - last_digest_epoch) < digest_min_spacing_seconds
        and phase != "reflective"
        and not overlay_activated
        and not phase_changed
    ):
        return False
    return phase_changed or overlay_activated or digest_key != str(state.get("last_digest_key") or "")


def render_digest(intent: str, evidence: str) -> str:
    return f"Session intent: {intent}. {evidence}."


def update_intent_engine(
    state: dict,
    payload: dict | None,
    now: int,
    modified_thresholds: dict,
    elapsed_thresholds: dict,
    digest_min_spacing_seconds: int,
    recommend_retrospective_fn,
    emit: bool = True,
):
    if payload:
        state = update_touched_files(state, extract_tool_paths(payload))

    previous_phase = str(state.get("intent_phase") or "quiet")
    if previous_phase not in PHASE_ORDER:
        previous_phase = "quiet"
    signals = compute_signal_snapshot(state, modified_thresholds, elapsed_thresholds, recommend_retrospective_fn)
    overlays = compute_overlays(state, signals)
    phase = advance_phase(state, signals, overlays)
    overlay_activated = any(overlays[key] and not bool(state.get(key)) for key in overlays)
    phase_changed = phase != previous_phase

    state["intent_phase"] = phase
    if phase_changed or int(state.get("intent_phase_epoch") or 0) == 0:
        state["intent_phase_epoch"] = now
    state["intent_phase_version"] = 1
    state["signal_edit_started"] = bool(signals["edit_started"])
    state["signal_scope_supporting"] = bool(signals["scope_supporting"])
    state["signal_scope_strong"] = bool(signals["scope_strong"])
    state["signal_work_supporting"] = bool(signals["work_supporting"])
    state["signal_work_strong"] = bool(signals["work_strong"])
    state["signal_compaction_seen"] = bool(signals["compaction_seen"])
    state["signal_idle_reset_seen"] = bool(signals["idle_reset_seen"])
    state["signal_cross_cutting"] = bool(signals["cross_cutting"])
    state["signal_scope_widening"] = bool(signals["scope_widening"])
    state["signal_reflection_likely"] = bool(signals["reflection_likely"])
    for key, value in overlays.items():
        state[key] = bool(value)

    digest = None
    if emit:
        intent, evidence = build_digest_intent(phase, overlays, signals)
        digest_key = build_digest_key(phase, overlays, intent)
        if should_emit_digest(
            state,
            phase,
            digest_key,
            phase_changed,
            overlay_activated,
            now,
            digest_min_spacing_seconds,
        ):
            digest = render_digest(intent, evidence)
            state["last_digest_key"] = digest_key
            state["last_digest_epoch"] = now
            state["digest_emit_count"] = int(state.get("digest_emit_count") or 0) + 1
    return state, digest