#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path


MANIFEST_FILES = {
    "package.json",
    "package-lock.json",
    "pyproject.toml",
    "requirements.txt",
    "requirements-dev.txt",
    "requirements-test.txt",
    "go.mod",
    "Cargo.toml",
    "release-please-config.json",
    ".release-please-manifest.json",
}


def unique_preserve(items):
    seen = set()
    ordered = []
    for item in items:
        if not item or item in seen:
            continue
        seen.add(item)
        ordered.append(item)
    return ordered


def normalize_path(raw_path) -> str:
    path_text = str(raw_path or "").strip().replace("\\", "/")
    if not path_text:
        return ""
    if path_text.startswith("./"):
        path_text = path_text[2:]
    try:
        candidate = Path(path_text)
        if candidate.is_absolute():
            try:
                path_text = str(candidate.resolve().relative_to(Path.cwd().resolve()))
            except Exception:
                path_text = candidate.name
    except Exception:
        pass
    return path_text.replace("\\", "/").lstrip("/")


def extract_tool_paths(payload: dict):
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return []

    paths = []

    def append_candidate(candidate):
        if isinstance(candidate, str):
            normalized = normalize_path(candidate)
            if normalized:
                paths.append(normalized)
            return
        if isinstance(candidate, dict):
            for key in ("filePath", "file", "path", "file_path"):
                value = candidate.get(key)
                if isinstance(value, str):
                    normalized = normalize_path(value)
                    if normalized:
                        paths.append(normalized)
                    return

    for key in ("filePath", "file", "path", "files", "file_path"):
        value = tool_input.get(key)
        if isinstance(value, list):
            for item in value:
                append_candidate(item)
        else:
            append_candidate(value)
    return unique_preserve(paths)


def classify_path_family(path_text: str):
    path_text = normalize_path(path_text)
    if not path_text:
        return None

    filename = Path(path_text).name
    if path_text.startswith(".copilot/workspace/"):
        return "memory"
    if path_text.startswith(".github/hooks/") or path_text.startswith("template/hooks/"):
        return "hook"
    if (
        path_text.startswith(".github/agents/")
        or path_text.startswith(".github/prompts/")
        or path_text.startswith(".github/instructions/")
        or path_text.startswith(".github/skills/")
        or path_text.startswith("template/prompts/")
        or path_text.startswith("template/instructions/")
        or path_text.startswith("template/skills/")
        or path_text in {"AGENTS.md", ".github/copilot-instructions.md", "template/copilot-instructions.md"}
    ):
        return "agent"
    if (
        path_text.startswith("tests/")
        or re.search(r"(^|/)(__tests__|test)/", path_text)
        or re.search(r"\.(test|spec)\.[^/]+$", path_text)
    ):
        return "tests"
    if (
        path_text.startswith(".github/workflows/")
        or path_text.startswith("scripts/release/")
        or path_text.startswith("scripts/sync/")
        or path_text.startswith("scripts/ci/")
        or path_text.startswith("scripts/workspace/")
    ):
        return "ci_release"
    if filename in MANIFEST_FILES:
        return "manifest"
    if (
        path_text.startswith(".vscode/")
        or re.search(r"(^|/)\.[^/]*rc(\.[^/]+)?$", path_text)
        or re.search(r"\.config\.[^/]+$", path_text)
    ):
        return "config"
    if path_text.endswith(".md") or filename in {
        "README.md",
        "CHANGELOG.md",
        "MIGRATION.md",
        "SETUP.md",
        "UPDATE.md",
        "VERSION.md",
        "CLAUDE.md",
        "llms.txt",
    }:
        return "docs"
    if path_text.startswith("scripts/") or path_text.endswith((".py", ".sh", ".ps1")):
        return "runtime"
    if path_text.endswith((".json", ".yml", ".yaml", ".toml")):
        return "config"
    return None


def path_requires_parity(path_text: str) -> bool:
    path_text = normalize_path(path_text)
    if not path_text:
        return False
    return (
        path_text.startswith(".github/hooks/")
        or path_text.startswith("template/hooks/")
        or path_text.startswith(".github/skills/")
        or path_text.startswith("template/skills/")
        or path_text.startswith(".github/instructions/")
        or path_text.startswith("template/instructions/")
        or path_text.startswith(".github/prompts/")
        or path_text.startswith("template/prompts/")
        or path_text in {
            ".copilot/workspace/operations/workspace-index.json",
            "template/workspace/operations/workspace-index.json",
        }
    )


def update_touched_files(state: dict, paths) -> dict:
    if not paths:
        return state
    touched = unique_preserve(list(state.get("touched_files_sample") or []) + list(paths))
    if len(touched) > 20:
        touched = touched[-20:]
    families = list(state.get("changed_path_families") or [])
    for path_text in paths:
        family = classify_path_family(path_text)
        if family and family not in families:
            families.append(family)
    state["touched_files_sample"] = touched
    state["unique_touched_file_count"] = len(touched)
    state["changed_path_families"] = families
    return state