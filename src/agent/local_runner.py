"""Local runner for the multi-agent orchestrator.

This module intentionally avoids AgentCore runtime, Cognito, GitHub App, and
AgentCore Memory dependencies at runtime. It uses the same orchestrator and
specialist agent factories with a local working directory and OpenAI-compatible
model credentials from environment variables.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import uuid

from strands import Agent
from openai import AsyncOpenAI
from strands import tool
from strands.models import OpenAIModel

from agents.engineer.agent import create_tool as create_engineer_tool
from agents.iac_tools import (
    checkov_scan,
    infracost_breakdown,
    terraform_init,
    terraform_plan,
    terraform_validate,
    ministack_terratest,
    tflint_scan,
)
from agents.orchestator.config import DESCRIPTION as ORCHESTRATOR_DESCRIPTION
from agents.orchestator.config import NAME as ORCHESTRATOR_NAME
from agents.orchestator.config import TOOL_NAMES as ORCHESTRATOR_TOOL_NAMES
from agents.orchestator.agent import create_agent as create_orchestrator_agent
from agents.orchestator.tools.opentofu_mcp import create_opentofu_mcp_client
from agents.reviewer.agent import create_tool as create_reviewer_tool
from agents.runtime import pick_tools
from agents.runtime import AgentRuntimeTools
from agents.skills.terrashark_plugin import TERRASHARK_SKILL_DIR, create_terrashark_plugin


CORE_EVAL_PROMPT = """# Orchestrator SOP

**Role**: Route IaC-Eval Terraform/OpenTofu benchmark work to Engineer and Reviewer only, then synthesize one concise final response.

## Required Eval Workflow
1. Delegate Terraform/OpenTofu implementation and file creation to `engineer_agent`.
2. Delegate a correctness review of the changed file paths to `reviewer_agent`.
3. If Reviewer returns blocking benchmark or deployability findings, delegate those findings and affected paths back to `engineer_agent`, then rerun `reviewer_agent`.
4. Limit Engineer to at most 3 total implementation/fix passes.
5. Do not call architect, security, FinOps/cost, DevOps, handoff, or pull request tools for this eval.
6. Do not apply infrastructure.

## Output
- Return changed files, validation commands/results reported by Engineer or Reviewer, reviewer findings, whether Engineer was recalled after review findings, Engineer pass count, and final Terraform summary.

## Constraints
- Only support AWS infrastructure and Terraform/OpenTofu with the AWS provider.
- Do not directly read, write, inspect, or modify files yourself. Delegate file operations to Engineer or Reviewer.
"""


class OpenRouterModel(OpenAIModel):
    """OpenAI-compatible model adapter that omits token-limit request fields."""

    def format_request(self, *args, **kwargs):
        request = super().format_request(*args, **kwargs)
        request.pop("max_tokens", None)
        request.pop("max_completion_tokens", None)
        return request


def load_env_file(path: Path) -> list[str]:
    if not path.exists():
        return []
    loaded: list[str] = []
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in os.environ:
            continue
        value = value.strip().strip('"').strip("'")
        os.environ[key] = value
        loaded.append(key)
    return loaded


def create_local_model() -> OpenAIModel:
    credentials = get_local_openai_credentials()
    return OpenRouterModel(
        client=AsyncOpenAI(
            api_key=credentials["api_key"],
            base_url=credentials["base_url"],
        ),
        model_id=credentials["model_id"],
        params={"temperature": float(os.environ.get("LOCAL_AGENT_TEMPERATURE", "0.1"))},
    )


def get_local_openai_credentials() -> dict[str, str]:
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise ValueError("OPENAI_API_KEY is required for local multi-agent runs.")
    return {
        "api_key": api_key,
        "base_url": os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"),
        "model_id": os.environ.get("OPENAI_MODEL_ID", "gpt-4o"),
    }


def _safe_workspace_path(path: str | None) -> Path:
    root = Path.cwd().resolve()
    requested = (path or "").strip() or "."
    candidate = (root / requested).resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError("path must stay inside the local workspace")
    return candidate


@tool(name="file_read")
def local_file_read(path: str) -> str:
    """Read a UTF-8 text file from the local workspace."""
    target = _safe_workspace_path(path)
    if not target.exists() or not target.is_file():
        return json.dumps({"ok": False, "error": "not_found", "path": path})
    return target.read_text(encoding="utf-8", errors="replace")


@tool(name="file_write")
def local_file_write(path: str, content: str) -> str:
    """Write a UTF-8 text file inside the local workspace without prompting."""
    target = _safe_workspace_path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(str(content), encoding="utf-8")
    return json.dumps({"ok": True, "path": target.relative_to(Path.cwd().resolve()).as_posix(), "bytes": target.stat().st_size})


def create_local_runtime_tools() -> AgentRuntimeTools:
    return AgentRuntimeTools(
        gateway=None,
        opentofu=create_opentofu_mcp_client(),
        handoff_to_user=None,
        file_read=local_file_read,
        file_write=local_file_write,
        terraform_init=terraform_init,
        terraform_plan=terraform_plan,
        terraform_validate=terraform_validate,
        ministack_terratest=ministack_terratest,
        tflint_scan=tflint_scan,
        infracost_breakdown=infracost_breakdown,
        checkov_scan=checkov_scan,
        diagram=None,
        swarm=None,
        create_pull_request=None,
    )


def create_core_eval_agent(model, runtime_tools: AgentRuntimeTools, trace_attributes: dict) -> Agent:
    own_tools = pick_tools(runtime_tools, ORCHESTRATOR_TOOL_NAMES)
    specialist_tools = [
        create_engineer_tool(model=model, runtime_tools=runtime_tools, trace_attributes={**trace_attributes, "specialist.agent": "engineer"}),
        create_reviewer_tool(model=model, runtime_tools=runtime_tools, trace_attributes={**trace_attributes, "specialist.agent": "reviewer"}),
    ]
    return Agent(
        model=model,
        name=ORCHESTRATOR_NAME,
        description=ORCHESTRATOR_DESCRIPTION,
        system_prompt=CORE_EVAL_PROMPT,
        tools=[*own_tools, *specialist_tools],
        plugins=[create_terrashark_plugin()],
        session_manager=None,
        trace_attributes=trace_attributes,
    )


def create_local_agent(session_id: str, workdir: Path, user_id: str = "local-user", agent_set: str = "full"):
    workdir.mkdir(parents=True, exist_ok=True)
    os.chdir(workdir)
    model = create_local_model()
    runtime_tools = create_local_runtime_tools()
    trace_attributes = {"user.id": user_id, "session.id": session_id, "runtime": "local", "agent.set": agent_set}
    if agent_set == "core":
        return create_core_eval_agent(
            model=model,
            runtime_tools=runtime_tools,
            trace_attributes=trace_attributes,
        )
    return create_orchestrator_agent(
        model=model,
        repository=None,
        state_backend=None,
        runtime_tools=runtime_tools,
        session_manager=None,
        trace_attributes=trace_attributes,
    )


def workspace_files(workdir: Path) -> list[str]:
    if not workdir.exists():
        return []
    files: list[str] = []
    for path in sorted(workdir.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(workdir).as_posix()
        if ".git/" in relative or relative == ".git":
            continue
        files.append(relative)
    return files


async def run_local_agent(prompt: str, workdir: Path, session_id: str, agent_set: str = "full") -> dict:
    agent = create_local_agent(session_id=session_id, workdir=workdir, agent_set=agent_set)
    agent.state.set("original_user_prompt", prompt)
    agent.state.set("original_user_context", prompt)

    chunks: list[str] = []
    tool_sequence: list[str] = []
    async for event in agent.stream_async(prompt):
        event_dict = dict(event)
        if isinstance(event_dict.get("data"), str):
            chunks.append(event_dict["data"])
            print(event_dict["data"], end="", flush=True)
        tool_use = event_dict.get("current_tool_use")
        if isinstance(tool_use, dict):
            name = str(tool_use.get("name") or "")
            if name and (not tool_sequence or tool_sequence[-1] != name):
                tool_sequence.append(name)
                print(f"\n[tool] {name}", flush=True)

    print("", flush=True)
    return {
        "sessionId": session_id,
        "workdir": str(workdir),
        "agentSet": agent_set,
        "toolSequence": tool_sequence,
        "response": "".join(chunks),
        "files": workspace_files(workdir),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the multi-agent orchestrator locally.")
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--prompt", help="Prompt text to send to the local orchestrator.")
    group.add_argument("--prompt-file", help="Path to a UTF-8 prompt file.")
    parser.add_argument("--workdir", default=".local-agent-runs/latest", help="Local workspace for generated files.")
    parser.add_argument("--session-id", default="", help="Optional stable local session id.")
    parser.add_argument("--summary-json", default="", help="Optional path to write a JSON run summary.")
    parser.add_argument("--env-file", default=".env", help="Optional dotenv file to load before reading local credentials.")
    parser.add_argument("--agent-set", choices=("full", "core"), default="full", help="Specialist tools available to the local orchestrator.")
    parser.add_argument("--dry-run", action="store_true", help="Validate local configuration and tool wiring without calling a model.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    loaded_env_keys = load_env_file(Path(args.env_file).expanduser()) if args.env_file else []
    session_id = args.session_id or f"local-{uuid.uuid4().hex[:12]}"
    workdir = Path(args.workdir).expanduser().resolve()
    summary_json = Path(args.summary_json).expanduser().resolve() if args.summary_json else None
    if args.dry_run:
        workdir.mkdir(parents=True, exist_ok=True)
        runtime_tools = create_local_runtime_tools()
        summary = {
            "dryRun": True,
            "sessionId": session_id,
            "workdir": str(workdir),
            "agentSet": args.agent_set,
            "openaiApiKeyConfigured": bool(os.environ.get("OPENAI_API_KEY", "").strip()),
            "openaiBaseUrl": os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"),
            "openaiModelId": os.environ.get("OPENAI_MODEL_ID", "gpt-4o"),
            "loadedEnvKeys": loaded_env_keys,
            "remoteOnlyToolsDisabled": {
                "gateway": runtime_tools.gateway is None,
                "opentofu": runtime_tools.opentofu is None,
                "handoff_to_user": runtime_tools.handoff_to_user is None,
                "create_pull_request": runtime_tools.create_pull_request is None,
            },
            "localToolsAvailable": {
                "file_read": runtime_tools.file_read is not None,
                "file_write": runtime_tools.file_write is not None,
                "terraform_init": runtime_tools.terraform_init is not None,
                "terraform_plan": runtime_tools.terraform_plan is not None,
                "terraform_validate": runtime_tools.terraform_validate is not None,
            },
            "localSkillsAvailable": {
                "terrashark": (TERRASHARK_SKILL_DIR / "SKILL.md").is_file(),
            },
            "files": workspace_files(workdir),
        }
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    else:
        if args.prompt is None and args.prompt_file is None:
            raise SystemExit("--prompt or --prompt-file is required unless --dry-run is used")
        prompt = args.prompt if args.prompt is not None else Path(args.prompt_file).read_text(encoding="utf-8")
        summary = asyncio.run(run_local_agent(prompt=prompt, workdir=workdir, session_id=session_id, agent_set=args.agent_set))
        summary["loadedEnvKeys"] = loaded_env_keys
    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        summary_json.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
