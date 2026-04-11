#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

from pulse_intent import update_intent_engine
from pulse_paths import extract_tool_paths
from pulse_state import (
    DEFAULT_POLICY,
    append_event,
    close_work_window,
    compute_session_medians,
    get_git_modified_file_count,
    iso_utc,
    load_policy,
    load_session_priors,
    load_state,
    prune_events,
    reflection_event_complete,
    recommend_retrospective,
    save_state,
    sentinel_is_complete,
    set_sentinel,
)


TRIGGER = os.environ.get("TRIGGER", "")
RAW_INPUT = os.environ.get("HOOK_INPUT", "")
NOW = int(time.time())
SCRIPT_DIR = Path(__file__).resolve().parent

WORKSPACE = Path(".copilot/workspace")
STATE_PATH = WORKSPACE / "runtime/state.json"
SENTINEL_PATH = WORKSPACE / "runtime/.heartbeat-session"
EVENTS_PATH = WORKSPACE / "runtime/.heartbeat-events.jsonl"
HEARTBEAT_PATH = WORKSPACE / "operations/HEARTBEAT.md"
POLICY_PATH = SCRIPT_DIR / "heartbeat-policy.json"
ROUTING_MANIFEST_PATH = Path(".github/agents/routing-manifest.json")


def parse_input(raw: str) -> dict:
    try:
        data = json.loads(raw) if raw.strip() else {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def retrospective_state(state: dict) -> str:
    return str(state.get("retrospective_state") or "idle")


def prompt_requests_retrospective(prompt: str) -> bool:
    if not re.search(r"\bretrospective\b", prompt, flags=re.IGNORECASE):
        return False
    if re.search(r"\b(no|skip|don't|do not|not now)\b.*\bretrospective\b", prompt, flags=re.IGNORECASE):
        return False
    if re.search(
        r"\b(explain|review|describe|summari[sz]e|discuss|compare|analy[sz]e|policy|threshold|logic|docs?|documentation|rules?)\b",
        prompt,
        flags=re.IGNORECASE,
    ):
        return False
    patterns = (
        r"^\s*retrospective(?:\s+(?:now|please))?\s*[?.!]*$",
        r"^\s*(?:run|do|start|perform)\s+(?:a\s+)?retrospective\b",
        r"\b(run|do|start|perform)\b.*\bretrospective\b",
        r"\b(can|could|would)\s+you\b.*\b(run|do|start|perform)\b.*\bretrospective\b",
        r"\bplease\b.*\b(run|do|start|perform)\b.*\bretrospective\b",
    )
    return any(re.search(pattern, prompt, flags=re.IGNORECASE) for pattern in patterns)


def prompt_requests_heartbeat_check(prompt: str) -> bool:
    if re.search(r"\b(no|skip|don't|do not)\b.*\b(heartbeat|health check)\b", prompt, flags=re.IGNORECASE):
        return False
    if re.search(
        r"\b(explain|review|describe|summari[sz]e|discuss|compare|analy[sz]e|policy|threshold|logic|docs?|documentation|rules?)\b",
        prompt,
        flags=re.IGNORECASE,
    ):
        return False
    patterns = (
        r"^\s*heartbeat(?:\s+now)?\s*[?.!]*$",
        r"^\s*(?:check|run)\s+(?:your\s+)?heartbeat\b",
        r"\b(check|run)\b.*\bheartbeat\b",
        r"\b(run|do)\b.*\bhealth check\b",
        r"\b(can|could|would)\s+you\b.*\b(check|run|do)\b.*\b(heartbeat|health check)\b",
    )
    return any(re.search(pattern, prompt, flags=re.IGNORECASE) for pattern in patterns)


def default_routing_manifest() -> dict:
    return {
        "version": 1,
        "default_cooldown_seconds": 900,
        "agents": [
            {
                "name": "Commit",
                "route": "active",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.74,
                "min_behavior_confidence": 0.75,
                "cooldown_seconds": 900,
                "min_behavior_events": 1,
                "hint": "Routing hint: Commit specialist fits this git lifecycle flow (stage/commit/push/tag).",
                "prompt_patterns": [
                    "\\bstage(?: and)? commit\\b",
                    "\\bcommit(?: message| my changes)?\\b",
                    "\\bpush(?: my changes| to origin)?\\b",
                    "\\btag(?: this version| as v)?\\b",
                    "\\bcreate (?:a )?release\\b",
                ],
                "behavior": {
                    "tool_names": ["run_in_terminal", "terminal", "runCommands"],
                    "command_patterns": [
                        "\\bgit\\s+(add|commit|push|tag|switch|checkout|merge|rebase|cherry-pick)\\b",
                        "\\bgit\\s+status\\b",
                    ],
                },
            },
            {
                "name": "Organise",
                "route": "active",
                "visibility": "internal",
                "min_prompt_confidence": 0.76,
                "min_behavior_confidence": 0.78,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "hint": "Routing hint: Organise specialist fits this file-move, path-fix, or repository-reshape workflow.",
                "prompt_patterns": [
                    "\\b(?:organize|organise|reorganize|reorganise)\\b",
                    "\\bmove files?\\b",
                    "\\bfix paths?\\b",
                    "\\brestructure\\b",
                    "\\brename (?:folders?|directories|files?)\\b",
                ],
                "behavior": {
                    "tool_names": ["run_in_terminal", "runCommands"],
                    "command_patterns": [
                        "\\bgit\\s+mv\\b",
                        "\\bmv\\s+[^\\n]+",
                    ],
                },
            },
            {
                "name": "Code",
                "route": "active",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.76,
                "min_behavior_confidence": 0.78,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "require_prompt_and_behavior": True,
                "hint": "Routing hint: Code specialist fits this multi-step implementation or refactor workflow.",
                "prompt_patterns": [
                    "\\bimplement\\b",
                    "\\brefactor\\b",
                    "\\bfeature\\b",
                    "\\badd (?:pagination|support|workflow|behavior|tests?)\\b",
                    "\\bwrite (?:or update )?tests?\\b",
                    "\\bbugfix\\b",
                ],
                "suppress_patterns": [
                    "\\b(review|audit|health check|security|research|upstream|docs?|documentation|readme|plan|break down|roadmap|scoping|root cause|regression|debug(?:ger)?|extensions?|profile|setup(?: from)?|update your instructions|restore instructions|factory restore|reinstall instructions|organi[sz]e|reorgani[sz]e|move files?|fix paths?)\\b"
                ],
                "behavior": {
                    "tool_names": [
                        "create_file",
                        "replace_string_in_file",
                        "multi_replace_string_in_file",
                        "editFiles",
                        "writeFile",
                    ]
                },
            },
            {
                "name": "Review",
                "route": "active",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.76,
                "min_behavior_confidence": 0.78,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "hint": "Routing hint: Review specialist fits this formal code-review or architecture-critique workflow.",
                "prompt_patterns": [
                    "\\breview\\b",
                    "\\bcode review\\b",
                    "\\bpr review\\b",
                    "\\barchitectural review\\b",
                    "\\bfindings\\b",
                ],
                "behavior": {
                    "tool_names": ["get_changed_files", "vscode_listCodeUsages"],
                    "command_patterns": [],
                },
            },
            {
                "name": "Fast",
                "route": "active",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.76,
                "min_behavior_confidence": 0.76,
                "cooldown_seconds": 900,
                "min_behavior_events": 1,
                "require_prompt_and_behavior": True,
                "hint": "Routing hint: Fast specialist fits this quick-question or lightweight single-file workflow.",
                "prompt_patterns": [
                    "\\bquick question\\b",
                    "\\bsyntax lookup\\b",
                    "\\bwhat does this regex match\\b",
                    "\\bfix (?:the )?typo\\b",
                    "\\bsingle-file(?: edit)?\\b",
                    "\\bwc\\s+-l\\b",
                ],
                "suppress_patterns": [
                    "\\b(implement|refactor|feature|bugfix|write tests?|review|audit|health check|security|research|upstream|docs?|documentation|readme|plan|break down|roadmap|scoping|root cause|regression|debug(?:ger)?|extensions?|profile|setup(?: from)?|update your instructions|restore instructions|factory restore|reinstall instructions|organi[sz]e|reorgani[sz]e|move files?|fix paths?|stage(?: and)? commit|push(?: my changes| to origin)?|create (?:a )?release)\\b"
                ],
                "behavior": {
                    "tool_names": ["run_in_terminal", "read_file", "editFiles"]
                },
            },
            {
                "name": "Audit",
                "route": "active",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.78,
                "min_behavior_confidence": 0.8,
                "cooldown_seconds": 1800,
                "min_behavior_events": 1,
                "hint": "Routing hint: Audit specialist fits this health-check, security, or residual-risk assessment flow.",
                "prompt_patterns": [
                    "\\baudit\\b",
                    "\\bhealth check\\b",
                    "\\bsecurity audit\\b",
                    "\\bscan for secrets?\\b",
                    "\\bvulnerabilit(?:y|ies)\\b",
                    "\\bresidual risk\\b",
                ],
                "behavior": {
                    "tool_names": ["run_in_terminal", "runCommands"],
                    "command_patterns": [
                        "\\b(copilot_audit\\.py|tests/scripts/test-copilot-audit\\.sh|scan-secrets)\\b",
                        "\\b(?:npm\\s+audit|pip-audit)\\b",
                    ],
                },
            },
            {
                "name": "Explore",
                "route": "active",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.74,
                "min_behavior_confidence": 0.72,
                "cooldown_seconds": 1200,
                "min_behavior_events": 2,
                "hint": "Routing hint: Explore specialist fits this read-only inventory/search workflow.",
                "prompt_patterns": [
                    "\\bexplore\\b",
                    "\\bread-only\\b",
                    "\\bfind (?:all|where|which)\\b",
                    "\\binventory\\b",
                    "\\bsearch (?:the )?(?:repo|codebase|workspace)\\b",
                    "\\bwhere is\\b",
                ],
                "behavior": {
                    "tool_names": [
                        "read_file",
                        "file_search",
                        "grep_search",
                        "semantic_search",
                        "list_dir",
                        "vscode_listCodeUsages",
                    ],
                    "path_patterns": [],
                },
            },
            {
                "name": "Extensions",
                "route": "active",
                "visibility": "internal",
                "min_prompt_confidence": 0.78,
                "min_behavior_confidence": 0.78,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "hint": "Routing hint: Extensions specialist fits this VS Code extension or profile-management workflow.",
                "prompt_patterns": [
                    "\\bextensions?\\b",
                    "\\bvs code extensions?\\b",
                    "\\bprofile\\b",
                    "\\bworkspace recommendation\\b",
                    "\\bsync extensions?\\b",
                ],
                "behavior": {
                    "tool_names": [
                        "get_active_profile",
                        "list_profiles",
                        "get_workspace_profile_association",
                        "ensure_repo_profile",
                        "get_installed_extensions",
                        "install_extension",
                        "uninstall_extension",
                        "sync_extensions_with_recommendations",
                    ],
                    "command_patterns": [],
                },
            },
            {
                "name": "Planner",
                "route": "active",
                "visibility": "internal",
                "min_prompt_confidence": 0.76,
                "min_behavior_confidence": 0.76,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "hint": "Routing hint: Planner specialist fits this scoped execution-planning workflow.",
                "prompt_patterns": [
                    "\\bplan\\b",
                    "\\bbreak down\\b",
                    "\\bexecution plan\\b",
                    "\\btask breakdown\\b",
                    "\\broadmap\\b",
                    "\\bscoping\\b",
                ],
                "behavior": {
                    "tool_names": ["read_file", "file_search", "grep_search", "semantic_search", "list_dir"],
                    "path_patterns": [],
                },
            },
            {
                "name": "Docs",
                "route": "active",
                "visibility": "internal",
                "min_prompt_confidence": 0.76,
                "min_behavior_confidence": 0.76,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "hint": "Routing hint: Docs specialist fits this documentation or migration-note workflow.",
                "prompt_patterns": [
                    "\\bdocument(?:ation)?\\b",
                    "\\bupdate (?:the )?(?:readme|docs?)\\b",
                    "\\bwrite (?:a )?(?:readme|guide|migration note)\\b",
                    "\\bwalkthrough\\b",
                    "\\buser-facing docs?\\b",
                ],
                "behavior": {
                    "tool_names": [
                        "create_file",
                        "replace_string_in_file",
                        "multi_replace_string_in_file",
                        "editFiles",
                        "writeFile",
                    ],
                    "path_patterns": ["\\.md$"],
                },
            },
            {
                "name": "Debugger",
                "route": "active",
                "visibility": "internal",
                "min_prompt_confidence": 0.78,
                "min_behavior_confidence": 0.8,
                "cooldown_seconds": 1200,
                "min_behavior_events": 1,
                "hint": "Routing hint: Debugger specialist fits this root-cause and regression-diagnosis workflow.",
                "prompt_patterns": [
                    "\\bdebug(?:ger)?\\b",
                    "\\broot cause\\b",
                    "\\bregression\\b",
                    "\\bfailing test\\b",
                    "\\bdiagnos(?:e|is)\\b",
                ],
                "behavior": {
                    "tool_names": ["run_in_terminal", "runCommands", "get_terminal_output"],
                    "command_patterns": [
                        "\\b(?:pytest|npm\\s+test|pnpm\\s+test|yarn\\s+test|go\\s+test|cargo\\s+test|bash\\s+tests/run-all\\.sh)\\b",
                        "\\btraceback\\b",
                    ],
                },
            },
            {
                "name": "Researcher",
                "route": "active",
                "visibility": "internal",
                "min_prompt_confidence": 0.78,
                "min_behavior_confidence": 0.78,
                "cooldown_seconds": 1800,
                "min_behavior_events": 1,
                "hint": "Routing hint: Researcher specialist fits this external-docs and version-check request.",
                "prompt_patterns": [
                    "\\bresearch\\b",
                    "\\blatest docs?\\b",
                    "\\bupstream\\b",
                    "\\bversion-specific\\b",
                    "\\bexternal docs?\\b",
                    "\\bapi behavior\\b",
                ],
                "behavior": {
                    "tool_names": ["fetch_webpage", "mcp_fetch_fetch", "fetch", "github_repo"],
                    "command_patterns": [],
                },
            },
            {
                "name": "Setup",
                "route": "guarded",
                "visibility": "picker-visible",
                "min_prompt_confidence": 0.92,
                "min_behavior_confidence": 0.86,
                "cooldown_seconds": 3600,
                "min_behavior_events": 1,
                "require_prompt_and_behavior": True,
                "block_in_template_repo": True,
                "hint": "Routing hint: Setup specialist fits this lifecycle-only setup/update/restore flow.",
                "prompt_patterns": [
                    "setup from asafelobotomy/copilot-instructions-template",
                    "\\bupdate your instructions\\b",
                    "\\bcheck for instruction updates\\b",
                    "\\brestore instructions from backup\\b",
                    "\\bfactory restore instructions\\b",
                    "\\breinstall instructions from scratch\\b",
                ],
                "suppress_patterns": [
                    "\\b(add|implement|refactor|fix|feature|bug|test|lint|build|code|script)\\b"
                ],
                "behavior": {
                    "tool_names": ["run_in_terminal", "runCommands"],
                    "command_patterns": [
                        "\\b(SETUP\\.md|UPDATE\\.md)\\b",
                        "\\b(update your instructions|factory restore|restore instructions from backup)\\b",
                    ],
                    "path_patterns": ["^(SETUP|UPDATE)\\.md$"]
                },
            },
        ],
    }


def load_routing_manifest(path: Path) -> dict:
    if not path.exists():
        return default_routing_manifest()
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict) and isinstance(loaded.get("agents"), list):
            return loaded
    except Exception:
        pass
    return default_routing_manifest()


def routing_index(manifest: dict) -> dict[str, dict]:
    index: dict[str, dict] = {}
    for entry in manifest.get("agents", []):
        if isinstance(entry, dict) and isinstance(entry.get("name"), str):
            index[entry["name"]] = entry
    return index


def is_template_repo() -> bool:
    return Path("template/copilot-instructions.md").exists() and Path(".github/copilot-instructions.md").exists()


def extract_command_text(payload: dict) -> str:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return ""
    for key in ("command", "cmd", "script", "query", "goal", "explanation"):
        value = tool_input.get(key)
        if isinstance(value, str) and value.strip():
            return value
    return ""


def compile_patterns(patterns) -> list[re.Pattern]:
    compiled = []
    for pattern in patterns or []:
        if not isinstance(pattern, str) or not pattern.strip():
            continue
        try:
            compiled.append(re.compile(pattern, re.IGNORECASE))
        except Exception:
            continue
    return compiled


def classify_prompt_route(prompt: str, manifest: dict) -> dict | None:
    if not prompt.strip():
        return None
    best = None
    for entry in manifest.get("agents", []):
        route_mode = str(entry.get("route") or "inactive")
        if route_mode not in {"active", "guarded"}:
            continue
        suppressors = compile_patterns(entry.get("suppress_patterns"))
        if any(regex.search(prompt) for regex in suppressors):
            continue
        patterns = compile_patterns(entry.get("prompt_patterns"))
        matches = [regex.pattern for regex in patterns if regex.search(prompt)]
        if not matches:
            continue
        confidence = min(0.99, 0.62 + 0.14 * len(matches))
        if route_mode == "guarded":
            confidence = min(0.99, confidence + 0.08)
        minimum = float(entry.get("min_prompt_confidence") or 0.75)
        if confidence < minimum:
            continue
        candidate = {
            "agent": entry["name"],
            "confidence": confidence,
            "reason": f"prompt:{matches[0]}",
            "route": route_mode,
        }
        if not best or candidate["confidence"] > best["confidence"]:
            best = candidate
    return best


def classify_behavior_route(payload: dict, state: dict, manifest: dict) -> dict | None:
    tool_name = str(payload.get("tool_name") or "")
    command_text = extract_command_text(payload)
    touched_paths = extract_tool_paths(payload)
    current_candidate = str(state.get("route_candidate") or "")
    best = None
    for entry in manifest.get("agents", []):
        route_mode = str(entry.get("route") or "inactive")
        if route_mode not in {"active", "guarded"}:
            continue
        if bool(entry.get("require_prompt_and_behavior")) and current_candidate and entry.get("name") != current_candidate:
            continue
        behavior = entry.get("behavior") or {}
        score = 0.0
        reasons: list[str] = []

        tool_names = {str(item) for item in behavior.get("tool_names") or [] if isinstance(item, str)}
        if tool_name and tool_name in tool_names:
            score += 0.48
            reasons.append(f"tool:{tool_name}")

        command_patterns = compile_patterns(behavior.get("command_patterns"))
        command_matched = False
        for regex in command_patterns:
            if command_text and regex.search(command_text):
                score += 0.32
                reasons.append(f"command:{regex.pattern}")
                command_matched = True
                break

        path_patterns = compile_patterns(behavior.get("path_patterns"))
        path_matched = False
        for regex in path_patterns:
            if any(regex.search(path_text) for path_text in touched_paths):
                score += 0.24
                reasons.append(f"path:{regex.pattern}")
                path_matched = True
                break

        if command_patterns and not command_matched and not path_matched:
            continue

        if score <= 0:
            continue
        signal_counts = state.get("route_signal_counts") or {}
        signal_key = entry["name"]
        seen_count = int(signal_counts.get(signal_key) or 0) + 1
        minimum_events = int(entry.get("min_behavior_events") or 1)
        confidence = min(0.99, 0.52 + score)
        minimum = float(entry.get("min_behavior_confidence") or 0.7)
        if seen_count < minimum_events or confidence < minimum:
            continue
        candidate = {
            "agent": entry["name"],
            "confidence": confidence,
            "reason": reasons[0],
            "seen_count": seen_count,
            "route": route_mode,
        }
        if not best or candidate["confidence"] > best["confidence"]:
            best = candidate
    return best


def should_emit_route_hint(state: dict, entry: dict, now: int, agent_name: str) -> bool:
    emitted_agents = state.get("route_emitted_agents") or []
    if agent_name in emitted_agents:
        return False
    cooldown = int(entry.get("cooldown_seconds") or 0)
    if cooldown <= 0:
        cooldown = int((ROUTING_MANIFEST.get("default_cooldown_seconds") or 900))
    last_hint_epoch = int(state.get("route_last_hint_epoch") or 0)
    if last_hint_epoch > 0 and (now - last_hint_epoch) < cooldown:
        return False
    if bool(state.get("route_emitted")) and str(state.get("route_candidate") or "") == agent_name:
        return False
    return True


def route_roster_text(manifest: dict) -> str:
    direct = []
    internal = []
    guarded = []
    for entry in manifest.get("agents", []):
        route_mode = str(entry.get("route") or "inactive")
        if route_mode not in {"active", "guarded"}:
            continue
        name = str(entry.get("name") or "")
        visibility = str(entry.get("visibility") or "internal")
        if route_mode == "guarded":
            guarded.append(name)
        elif visibility == "picker-visible":
            direct.append(name)
        else:
            internal.append(name)
    parts = []
    if direct:
        parts.append("specialists: " + ", ".join(direct))
    if internal:
        parts.append("internal: " + ", ".join(internal))
    if guarded:
        parts.append("guarded: " + ", ".join(guarded))
    return " | ".join(parts)


def print_json(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=True))


POLICY = load_policy(POLICY_PATH)
ROUTING_MANIFEST = load_routing_manifest(ROUTING_MANIFEST_PATH)
ROUTING_INDEX = routing_index(ROUTING_MANIFEST)
RETRO_POLICY = POLICY.get("retrospective", DEFAULT_POLICY["retrospective"])
RETRO_THRESHOLDS = RETRO_POLICY.get("thresholds", DEFAULT_POLICY["retrospective"]["thresholds"])
RETRO_MODIFIED_THRESHOLDS = RETRO_THRESHOLDS.get(
    "modified_files", DEFAULT_POLICY["retrospective"]["thresholds"]["modified_files"]
)
RETRO_ELAPSED_THRESHOLDS = RETRO_THRESHOLDS.get(
    "elapsed_minutes", DEFAULT_POLICY["retrospective"]["thresholds"]["elapsed_minutes"]
)
IDLE_GAP_MINUTES = int(RETRO_THRESHOLDS.get("idle_gap_minutes") or 10)
HEALTH_DIGEST_CONFIG = RETRO_POLICY.get("health_digest", DEFAULT_POLICY["retrospective"]["health_digest"])
HEALTH_DIGEST_MIN_SPACING_SECONDS = int(HEALTH_DIGEST_CONFIG.get("min_emit_spacing_seconds") or 120)
RETRO_MESSAGES = RETRO_POLICY.get("messages", DEFAULT_POLICY["retrospective"]["messages"])
SESSION_START_GUIDANCE = str(
    RETRO_MESSAGES.get("session_start_guidance")
    or DEFAULT_POLICY["retrospective"]["messages"]["session_start_guidance"]
)
EXPLICIT_SYSTEM_MESSAGE = str(
    RETRO_MESSAGES.get("explicit_system")
    or DEFAULT_POLICY["retrospective"]["messages"]["explicit_system"]
)
STOP_REFLECT_INSTRUCTION = str(
    RETRO_MESSAGES.get("stop_reflect_instruction")
    or DEFAULT_POLICY["retrospective"]["messages"]["stop_reflect_instruction"]
)
ACCEPTED_REASON = str(
    RETRO_MESSAGES.get("accepted_reason")
    or DEFAULT_POLICY["retrospective"]["messages"]["accepted_reason"]
)
def build_recommendation(state: dict) -> tuple[bool, str]:
    return recommend_retrospective(state, RETRO_MODIFIED_THRESHOLDS, RETRO_ELAPSED_THRESHOLDS)


payload = parse_input(RAW_INPUT)
state = load_state(STATE_PATH)

provided_id = str(payload.get("sessionId") or "")
if provided_id:
    session_id = provided_id
elif TRIGGER == "session_start":
    session_id = f"local-{os.urandom(4).hex()}"
else:
    session_id = state.get("session_id") or "unknown"
state["session_id"] = session_id
state["last_trigger"] = TRIGGER

if TRIGGER == "session_start":
    state.update(load_session_priors(WORKSPACE))
    state["session_state"] = "pending"
    state["retrospective_state"] = "idle"
    state["last_write_epoch"] = NOW
    state["session_start_epoch"] = NOW
    state["session_start_git_count"] = get_git_modified_file_count()
    state["task_window_start_epoch"] = 0
    state["last_raw_tool_epoch"] = 0
    state["active_work_seconds"] = 0
    state["copilot_edit_count"] = 0
    state["tool_call_counter"] = 0
    state["intent_phase"] = "quiet"
    state["intent_phase_epoch"] = NOW
    state["intent_phase_version"] = 1
    state["last_digest_key"] = ""
    state["last_digest_epoch"] = 0
    state["digest_emit_count"] = 0
    state["overlay_sensitive_surface"] = False
    state["overlay_parity_required"] = False
    state["overlay_verification_expected"] = False
    state["overlay_decision_capture_needed"] = False
    state["overlay_retro_requested"] = False
    state["signal_edit_started"] = False
    state["signal_scope_supporting"] = False
    state["signal_scope_strong"] = False
    state["signal_work_supporting"] = False
    state["signal_work_strong"] = False
    state["signal_compaction_seen"] = False
    state["signal_idle_reset_seen"] = False
    state["signal_cross_cutting"] = False
    state["signal_scope_widening"] = False
    state["signal_reflection_likely"] = False
    state["route_candidate"] = ""
    state["route_reason"] = ""
    state["route_confidence"] = 0.0
    state["route_source"] = ""
    state["route_emitted"] = False
    state["route_epoch"] = 0
    state["route_last_hint_epoch"] = 0
    state["route_emitted_agents"] = []
    state["route_signal_counts"] = {}
    state["changed_path_families"] = []
    state["touched_files_sample"] = []
    state["unique_touched_file_count"] = 0
    set_sentinel(SENTINEL_PATH, WORKSPACE, NOW, session_id, "pending")
    append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, session_id=session_id)
    prune_events(EVENTS_PATH)
    save_state(state, WORKSPACE, STATE_PATH)
    ctx_parts = [
        f"Session started at {iso_utc(NOW)}.",
        *([compute_session_medians(EVENTS_PATH)] if compute_session_medians(EVENTS_PATH) else []),
        f"Routing roster: {route_roster_text(ROUTING_MANIFEST)}.",
        SESSION_START_GUIDANCE,
    ]
    print_json({
        "continue": True,
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": " ".join(ctx_parts),
        },
    })
    raise SystemExit(0)

if TRIGGER == "pre_tool":
    signal_counts = state.get("route_signal_counts") or {}
    behavior_candidate = classify_behavior_route(payload, state, ROUTING_MANIFEST)
    if behavior_candidate:
        signal_counts[behavior_candidate["agent"]] = int(signal_counts.get(behavior_candidate["agent"]) or 0) + 1
        state["route_signal_counts"] = signal_counts

    current_candidate = str(state.get("route_candidate") or "")
    current_conf = float(state.get("route_confidence") or 0.0)
    if behavior_candidate:
        agent_name = behavior_candidate["agent"]
        entry = ROUTING_INDEX.get(agent_name, {})
        requires_prompt_and_behavior = bool(entry.get("require_prompt_and_behavior"))
        guarded = str(entry.get("route") or "") == "guarded"
        if requires_prompt_and_behavior:
            if str(state.get("route_candidate") or "") != agent_name:
                save_state(state, WORKSPACE, STATE_PATH)
                print_json({"continue": True})
                raise SystemExit(0)
        if guarded:
            if bool(entry.get("block_in_template_repo")) and is_template_repo():
                save_state(state, WORKSPACE, STATE_PATH)
                print_json({"continue": True})
                raise SystemExit(0)

        if current_candidate == agent_name:
            state["route_confidence"] = max(current_conf, float(behavior_candidate["confidence"]))
            state["route_reason"] = f"{state.get('route_reason')}; behavior:{behavior_candidate['reason']}"
            state["route_source"] = "prompt+behavior"
        elif not current_candidate:
            state["route_candidate"] = agent_name
            state["route_confidence"] = float(behavior_candidate["confidence"])
            state["route_reason"] = f"behavior:{behavior_candidate['reason']}"
            state["route_source"] = "behavior"
            state["route_emitted"] = False
            state["route_epoch"] = NOW

        candidate_name = str(state.get("route_candidate") or "")
        candidate_entry = ROUTING_INDEX.get(candidate_name, {})
        candidate_conf = float(state.get("route_confidence") or 0.0)
        min_behavior = float(candidate_entry.get("min_behavior_confidence") or 0.7)
        if (
            candidate_name
            and behavior_candidate["agent"] == candidate_name
            and candidate_conf >= min_behavior
            and should_emit_route_hint(state, candidate_entry, NOW, candidate_name)
        ):
            hint = str(candidate_entry.get("hint") or f"Routing hint: {candidate_name} specialist may be the best fit.")
            emitted_agents = list(state.get("route_emitted_agents") or [])
            emitted_agents.append(candidate_name)
            state["route_emitted_agents"] = emitted_agents
            state["route_emitted"] = True
            state["route_last_hint_epoch"] = NOW
            state["last_write_epoch"] = NOW
            save_state(state, WORKSPACE, STATE_PATH)
            print_json({
                "continue": True,
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": f"{hint} Confidence {candidate_conf:.2f} ({state.get('route_source')}).",
                },
            })
            raise SystemExit(0)

    state["last_write_epoch"] = NOW
    save_state(state, WORKSPACE, STATE_PATH)
    print_json({"continue": True})
    raise SystemExit(0)

if TRIGGER == "soft_post_tool":
    file_writing_tools = {
        "create_file",
        "replace_string_in_file",
        "multi_replace_string_in_file",
        "editFiles",
        "writeFile",
    }
    if str(payload.get("tool_name") or "") in file_writing_tools:
        state["copilot_edit_count"] = int(state.get("copilot_edit_count") or 0) + 1

    idle_gap_seconds = IDLE_GAP_MINUTES * 60
    task_window_start = int(state.get("task_window_start_epoch") or 0)
    last_tool = int(state.get("last_raw_tool_epoch") or 0)
    if task_window_start == 0:
        state["task_window_start_epoch"] = NOW
    elif last_tool > 0 and (NOW - last_tool) > idle_gap_seconds:
        state["active_work_seconds"] = int(state.get("active_work_seconds") or 0) + max(0, last_tool - task_window_start)
        state["task_window_start_epoch"] = NOW
        state["signal_idle_reset_seen"] = True
    state["last_raw_tool_epoch"] = NOW
    state["last_write_epoch"] = NOW
    state["tool_call_counter"] = int(state.get("tool_call_counter") or 0) + 1

    if NOW - int(state.get("last_soft_trigger_epoch") or 0) >= 300:
        state["last_soft_trigger_epoch"] = NOW
        append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, session_id=session_id)

    state, digest = update_intent_engine(
        state,
        payload,
        NOW,
        RETRO_MODIFIED_THRESHOLDS,
        RETRO_ELAPSED_THRESHOLDS,
        HEALTH_DIGEST_MIN_SPACING_SECONDS,
        build_recommendation,
        emit=True,
    )
    save_state(state, WORKSPACE, STATE_PATH)
    if digest:
        print_json({
            "continue": True,
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": digest,
            },
        })
    else:
        print_json({"continue": True})
    raise SystemExit(0)

if TRIGGER == "compaction":
    state = close_work_window(state)
    state["last_compaction_epoch"] = NOW
    state["last_write_epoch"] = NOW
    append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, session_id=session_id)
    state, _digest = update_intent_engine(
        state,
        None,
        NOW,
        RETRO_MODIFIED_THRESHOLDS,
        RETRO_ELAPSED_THRESHOLDS,
        HEALTH_DIGEST_MIN_SPACING_SECONDS,
        build_recommendation,
        emit=False,
    )
    save_state(state, WORKSPACE, STATE_PATH)
    print_json({"continue": True})
    raise SystemExit(0)

if TRIGGER in ("user_prompt", "explicit"):
    prompt = str(payload.get("prompt") or "")
    prompt_candidate = classify_prompt_route(prompt, ROUTING_MANIFEST)
    if prompt_candidate:
        state["route_candidate"] = prompt_candidate["agent"]
        state["route_reason"] = prompt_candidate["reason"]
        state["route_confidence"] = float(prompt_candidate["confidence"])
        state["route_source"] = "prompt"
        state["route_emitted"] = False
        state["route_epoch"] = NOW
        state["route_signal_counts"] = {}
    else:
        state["route_candidate"] = ""
        state["route_reason"] = ""
        state["route_confidence"] = 0.0
        state["route_source"] = ""
        state["route_emitted"] = False
        state["route_epoch"] = 0
        state["route_signal_counts"] = {}
    retrospective_requested = prompt_requests_retrospective(prompt)
    heartbeat_requested = prompt_requests_heartbeat_check(prompt)
    if retrospective_requested:
        state["retrospective_state"] = "accepted"

    if heartbeat_requested or retrospective_requested:
        state["last_explicit_epoch"] = NOW
        state["last_write_epoch"] = NOW
        append_event(
            EVENTS_PATH,
            WORKSPACE,
            NOW,
            "explicit_prompt",
            "heartbeat" if heartbeat_requested else "retrospective",
            session_id=session_id,
        )
        state, _digest = update_intent_engine(
            state,
            None,
            NOW,
            RETRO_MODIFIED_THRESHOLDS,
            RETRO_ELAPSED_THRESHOLDS,
            HEALTH_DIGEST_MIN_SPACING_SECONDS,
            build_recommendation,
            emit=False,
        )
        save_state(state, WORKSPACE, STATE_PATH)
        if heartbeat_requested:
            print_json({"continue": True, "systemMessage": EXPLICIT_SYSTEM_MESSAGE})
        else:
            print_json({"continue": True})
    else:
        state["last_write_epoch"] = NOW
        save_state(state, WORKSPACE, STATE_PATH)
        print_json({"continue": True})
    raise SystemExit(0)

if TRIGGER == "stop":
    if bool(payload.get("stop_hook_active", False)):
        print_json({"continue": True})
        raise SystemExit(0)

    state = close_work_window(state)
    session_start_epoch = int(state.get("session_start_epoch") or 0)
    retro_ran = sentinel_is_complete(SENTINEL_PATH) or reflection_event_complete(
        EVENTS_PATH,
        session_id,
        session_start_epoch,
    )

    duration_seconds = max(0, NOW - session_start_epoch)
    if retro_ran:
        state["session_state"] = "complete"
        state["retrospective_state"] = "complete"
        state["last_write_epoch"] = NOW
        set_sentinel(SENTINEL_PATH, WORKSPACE, NOW, session_id, "complete")
        append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, "complete", duration_seconds, session_id=session_id)
        save_state(state, WORKSPACE, STATE_PATH)
        print_json({"continue": True})
        raise SystemExit(0)

    if retrospective_state(state) == "accepted":
        state["session_state"] = "pending"
        state["last_write_epoch"] = NOW
        append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, "accepted-pending", session_id=session_id)
        save_state(state, WORKSPACE, STATE_PATH)
        print_json({
            "hookSpecificOutput": {
                "hookEventName": "Stop",
                "decision": "block",
                "reason": ACCEPTED_REASON,
            }
        })
        raise SystemExit(0)

    should_reflect, basis = build_recommendation(state)
    if should_reflect:
        state["session_state"] = "pending"
        state["retrospective_state"] = "suggested"
        state["last_write_epoch"] = NOW
        append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, "reflect-needed", session_id=session_id)
        save_state(state, WORKSPACE, STATE_PATH)
        print_json({
            "hookSpecificOutput": {
                "hookEventName": "Stop",
                "decision": "block",
                "reason": f"Significant session ({basis}). {STOP_REFLECT_INSTRUCTION}",
            }
        })
        raise SystemExit(0)

    state["session_state"] = "complete"
    state["retrospective_state"] = "not-needed"
    state["last_write_epoch"] = NOW
    append_event(EVENTS_PATH, WORKSPACE, NOW, TRIGGER, "not-needed", duration_seconds, session_id=session_id)
    save_state(state, WORKSPACE, STATE_PATH)
    print_json({"continue": True})
    raise SystemExit(0)

print_json({"continue": True})