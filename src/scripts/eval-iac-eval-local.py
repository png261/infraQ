#!/usr/bin/env python3
"""Evaluate the local multi-agent runner on IaC-Eval rows.

This mirrors the deployed chat evaluator's spreadsheet output and official
Terraform plan + OPA/Rego check, but it runs `agent/local_runner.py` directly
with credentials loaded from a local dotenv file.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import importlib.util
import json
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
EVAL_PATH = SCRIPT_DIR / "eval-iac-eval-chat.py"
AGENT_DIR = ROOT / "agent"

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(1, str(AGENT_DIR))

import local_runner


def load_eval_module():
    spec = importlib.util.spec_from_file_location("iac_eval_chat", EVAL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {EVAL_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


eval_chat = load_eval_module()

CORE_AGENT_NAMES = [
    "engineer_agent",
    "reviewer_agent",
]


def required_agents(agent_set: str) -> list[str]:
    if agent_set == "core":
        return CORE_AGENT_NAMES
    return list(eval_chat.AGENT_NAMES)


def build_local_prompt(row: dict[str, str], agent_set: str) -> str:
    if agent_set != "core":
        return eval_chat.build_prompt(row)
    resource = eval_chat.clean(row.get("Resource"))
    prompt = eval_chat.clean(row.get("Prompt"))
    difficulty = eval_chat.clean(row.get("Difficulty"))
    intent = eval_chat.clean(row.get("Intent"))
    return f"""Use this as an IaC-Eval benchmark task for AWS Terraform/OpenTofu generation.

Benchmark row:
- Resource: {resource}
- Difficulty: {difficulty}
- Prompt: {prompt}
- Intent: {intent}

Rules:
- Do not ask me for more information unless the benchmark row is impossible or unsafe.
- Do not use any reference answer.
- Create a minimal deployable Terraform/OpenTofu solution for AWS only.
- Use provider "aws" and region "us-east-1" unless the task explicitly requires another region.
- Do not apply infrastructure.
- Keep validation plan-only.

Eval workflow to test:
1. Orchestrator: manage the workflow and final response.
2. Engineer: write the Terraform/OpenTofu files.
3. Reviewer: check correctness against the benchmark prompt and likely Rego intent.
4. If Reviewer returns a finding that requires Terraform/file changes, send the finding back to Engineer, have Engineer update the files, then rerun Reviewer before finalizing.
5. Limit Engineer to at most 3 total implementation/fix passes for this benchmark row; after 3 Engineer calls, stop fixing and finalize with the remaining findings.

Do not call architect_agent, security_prover_agent, cost_capacity_agent, devops_agent, handoff_to_user, or create_pull_request during this eval.

Return changed files, validation commands/results, reviewer findings, whether Engineer was recalled after Reviewer findings, Engineer pass count, and final Terraform summary."""


def tf_contents(source_dir: Path) -> dict[str, str]:
    return {
        str(path.relative_to(source_dir)): path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(source_dir.rglob("*.tf"))
        if ".terraform" not in path.relative_to(source_dir).parts
    }


def tfvars_contents(source_dir: Path) -> dict[str, str]:
    return {
        str(path.relative_to(source_dir)): path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(source_dir.rglob("*.tfvars"))
        if ".terraform" not in path.relative_to(source_dir).parts
    }


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, default=str), encoding="utf-8")


def run_local_prompt(prompt: str, workdir: Path, summary_path: Path, session_id: str, agent_set: str) -> dict[str, Any]:
    original_cwd = Path.cwd()
    try:
        result = asyncio.run(local_runner.run_local_agent(prompt=prompt, workdir=workdir, session_id=session_id, agent_set=agent_set))
        result["loadedEnvKeys"] = []
        write_json(summary_path, result)
        return result
    finally:
        os.chdir(original_cwd)


def build_record(
    row: dict[str, str],
    index: int,
    output_dir: Path,
    official_eval: bool,
    terraform_bin: str,
    opa_bin: str,
    official_timeout: int,
    terraform_plugin_cache_dir: str,
    agent_set: str,
) -> dict[str, Any]:
    started = time.time()
    session_id = f"local-{uuid.uuid4().hex[:12]}"
    source_dir = output_dir / "generated-source" / f"row-{index:04d}-{session_id}"
    summary_path = output_dir / "run-summaries" / f"row-{index:04d}-{session_id}.json"
    markers = eval_chat.required_markers_for_row(row)
    try:
        summary = run_local_prompt(build_local_prompt(row, agent_set), source_dir, summary_path, session_id, agent_set)
        file_contents = {**tf_contents(source_dir), **tfvars_contents(source_dir)}
        terraform_files = sorted(file_contents)
        generated_code = "\n\n".join(file_contents.values())
        reference_output = eval_chat.clean(row.get("Reference output") or row.get("Reference Output"))
        combined = f"{summary.get('response', '')}\n{generated_code}"
        marker_results = {marker: marker in combined for marker in markers}
        missing_markers = [marker for marker, found in marker_results.items() if not found]
        tool_sequence = list(summary.get("toolSequence") or [])
        tool_names = sorted(set(tool_sequence), key=tool_sequence.index)
        engineer_loop = eval_chat.smoke.engineer_loop_summary(tool_sequence)
        expected_agents = required_agents(agent_set)
        all_agents_called = all(agent in tool_names for agent in expected_agents)
        artifact_quality = eval_chat.artifact_quality_check(source_dir, file_contents)
        official = eval_chat.run_official_iac_eval(
            source_dir,
            eval_chat.rego_policy_for_row(row),
            official_eval,
            terraform_bin,
            opa_bin,
            official_timeout,
            terraform_plugin_cache_dir,
        )
        passed = bool(summary.get("response", "").strip()) and bool(terraform_files) and all_agents_called
        if official_eval:
            passed = bool(passed and official.get("officialPass"))
        else:
            passed = bool(passed and all(marker_results.values()))
        record = {
            "index": index,
            "rowId": eval_chat.row_id(index, row),
            "status": "completed",
            "pass": passed,
            "stack": "local",
            "region": "local",
            "agentSet": agent_set,
            "sessionId": session_id,
            "userId": "local-user",
            "durationSeconds": round(time.time() - started, 2),
            "difficulty": eval_chat.clean(row.get("Difficulty")),
            "resource": eval_chat.clean(row.get("Resource")),
            "prompt": eval_chat.clean(row.get("Prompt")),
            "intent": eval_chat.clean(row.get("Intent")),
            "referenceOutput": reference_output,
            "bleuScore": round(eval_chat.bleu_score(reference_output, generated_code), 6),
            "eventCount": len(tool_sequence),
            "toolNames": tool_names,
            "toolCallSequence": tool_sequence,
            "engineerLoop": engineer_loop,
            "allAgentsCalled": all_agents_called,
            "specialistProgress": {
                "startedAgents": tool_names,
                "completedAgents": tool_names,
                "missingAgents": [agent for agent in expected_agents if agent not in tool_names],
            },
            "terraformFiles": terraform_files,
            "generatedSourceDir": str(source_dir),
            "generatedSourceFiles": [str((source_dir / file).relative_to(output_dir)) for file in terraform_files],
            "artifactQuality": artifact_quality,
            "officialEvaluation": official,
            "requiredMarkers": marker_results,
            "missingMarkers": missing_markers,
            "allRequiredMarkersFound": all(marker_results.values()),
            "responsePreview": str(summary.get("response", ""))[:1200],
            "summaryJson": str(summary_path),
        }
        failure = eval_chat.failure_summary(record)
        record["failure_category"] = failure["failureCategory"]
        record["failure_reason"] = failure["failureReason"]
        return record
    except Exception as exc:
        record = {
            "index": index,
            "rowId": eval_chat.row_id(index, row),
            "status": "error",
            "pass": False,
            "stack": "local",
            "region": "local",
            "agentSet": agent_set,
            "sessionId": session_id,
            "userId": "local-user",
            "durationSeconds": round(time.time() - started, 2),
            "difficulty": eval_chat.clean(row.get("Difficulty")),
            "resource": eval_chat.clean(row.get("Resource")),
            "prompt": eval_chat.clean(row.get("Prompt")),
            "intent": eval_chat.clean(row.get("Intent")),
            "error": str(exc),
            "generatedSourceDir": str(source_dir),
            "summaryJson": str(summary_path),
        }
        failure = eval_chat.failure_summary(record)
        record["failure_category"] = failure["failureCategory"]
        record["failure_reason"] = failure["failureReason"]
        return record


def write_jsonl(jsonl_path: Path, record: dict[str, Any]) -> None:
    jsonl_path.parent.mkdir(parents=True, exist_ok=True)
    with jsonl_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")


def is_auth_error(record: dict[str, Any]) -> bool:
    error_text = " ".join(
        str(record.get(key, ""))
        for key in ("error", "failure_reason", "failureReason")
    )
    failure = record.get("failure") if isinstance(record.get("failure"), dict) else {}
    error_text = f"{error_text} {failure.get('failureReason', '')}"
    return "INVALID_API_KEY" in error_text or "AuthenticationError" in error_text or "authentication_error" in error_text


def completed_indices_for_resume(jsonl_path: Path) -> set[int]:
    done: set[int] = set()
    if not jsonl_path.exists():
        return done
    with jsonl_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            index = item.get("index")
            if not isinstance(index, int):
                continue
            failure = item.get("failure") if isinstance(item.get("failure"), dict) else {}
            failure_category = item.get("failure_category") or failure.get("failureCategory")
            if item.get("status") == "error" and (failure_category == "runtime_error" or is_auth_error(item)):
                continue
            done.add(index)
    return done


def rewrite_csv(csv_path: Path, jsonl_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, Any]] = []
    if jsonl_path.exists():
        with jsonl_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    rows.append(eval_chat.flatten_for_sheet(json.loads(line)))
                except json.JSONDecodeError:
                    continue
    fieldnames = [
        "index",
        "row_id",
        "status",
        "pass",
        "failure_category",
        "failure_reason",
        "duration_seconds",
        "session_id",
        "difficulty",
        "resource",
        "prompt",
        "intent",
        "bleu_score",
        "agents_called",
        "tool_call_sequence",
        "all_agents_called",
        "engineer_call_count",
        "engineer_after_reviewer",
        "engineer_after_verifier",
        "terraform_files",
        "generated_source_dir",
        "generated_source_files",
        "artifact_complete_pass",
        "artifact_missing_files",
        "quality_gate_pass",
        "quality_findings_json",
        "official_eval_enabled",
        "official_plan_success",
        "official_opa_result",
        "official_pass",
        "official_error",
        "required_marker_count",
        "found_marker_count",
        "all_required_markers_found",
        "required_markers",
        "missing_markers",
        "marker_results_json",
        "event_count",
        "started_agents",
        "completed_agents",
        "error",
        "response_preview",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_summary(output_dir: Path, jsonl_path: Path, csv_path: Path) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    if jsonl_path.exists():
        with jsonl_path.open("r", encoding="utf-8") as handle:
            records = [json.loads(line) for line in handle if line.strip()]
    summary = {
        "rows": len(records),
        "passed": sum(1 for record in records if record.get("pass")),
        "failed": sum(1 for record in records if not record.get("pass")),
        "officialPassed": sum(1 for record in records if (record.get("officialEvaluation") or {}).get("officialPass")),
        "planPassed": sum(1 for record in records if (record.get("officialEvaluation") or {}).get("terraformPlanSuccess")),
        "opaPassed": sum(1 for record in records if (record.get("officialEvaluation") or {}).get("opaEvaluationResult") == "Success"),
        "allAgentsCalled": sum(1 for record in records if record.get("allAgentsCalled")),
        "avgBleuScore": sum(float(record.get("bleuScore") or 0) for record in records) / len(records) if records else 0,
        "jsonl": str(jsonl_path),
        "csv": str(csv_path),
    }
    write_json(output_dir / "summary.json", summary)
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-file", default="")
    parser.add_argument("--dataset-url", default=eval_chat.DEFAULT_DATASET_URL)
    parser.add_argument("--output-dir", default="eval-results/iac-eval-local")
    parser.add_argument("--env-file", default=".env")
    parser.add_argument("--agent-set", choices=("full", "core"), default="core", help="Specialist set for local eval. core keeps only engineer_agent and reviewer_agent.")
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--limit", type=int, default=3)
    parser.add_argument("--indices-file", default="", help="Optional newline/comma separated dataset indices to run.")
    parser.add_argument("--full", action="store_true", help="Run all remaining rows.")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--no-stop-on-auth-error", action="store_true", help="Continue after model authentication errors instead of stopping immediately.")
    parser.add_argument("--confirm-cost", action="store_true", help="Required for --full.")
    parser.add_argument("--official-eval", action="store_true", help="Run upstream-style Terraform plan plus OPA/Rego evaluation.")
    parser.add_argument("--terraform-bin", default="terraform")
    parser.add_argument("--opa-bin", default="opa")
    parser.add_argument("--official-timeout", type=int, default=120)
    parser.add_argument("--terraform-plugin-cache-dir", default=str(eval_chat.DEFAULT_TERRAFORM_PLUGIN_CACHE_DIR))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.full and not args.confirm_cost:
        raise SystemExit("--full requires --confirm-cost because this can run for many hours and incur model/runtime cost")
    loaded_keys = local_runner.load_env_file(Path(args.env_file).expanduser()) if args.env_file else []
    local_runner.get_local_openai_credentials()
    rows = eval_chat.load_dataset_rows(args.dataset_file or None, args.dataset_url)
    selected = list(enumerate(rows))
    indices = eval_chat.load_indices(args.indices_file)
    if indices:
        selected = [(index, row) for index, row in selected if index in indices]
    if args.start:
        selected = [(index, row) for index, row in selected if index >= args.start]
    if not args.full:
        selected = selected[: args.limit]

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = output_dir / "iac_eval_local_results.jsonl"
    csv_path = output_dir / "iac_eval_local_results.csv"
    done = completed_indices_for_resume(jsonl_path) if args.resume else set()

    print(json.dumps({"selectedRows": len(selected), "loadedEnvKeys": loaded_keys, "outputDir": str(output_dir), "agentSet": args.agent_set}, indent=2), flush=True)
    for index, row in selected:
        if index in done:
            print(f"Skipping completed IaC-Eval row {index}", flush=True)
            continue
        print(f"Running local IaC-Eval row {index}: difficulty={eval_chat.clean(row.get('Difficulty'))} resource={eval_chat.clean(row.get('Resource'))[:120]}", flush=True)
        record = build_record(
            row,
            index,
            output_dir,
            args.official_eval,
            args.terraform_bin,
            args.opa_bin,
            args.official_timeout,
            args.terraform_plugin_cache_dir,
            args.agent_set,
        )
        if is_auth_error(record) and not args.no_stop_on_auth_error:
            print("Stopping after model authentication error. Fix the configured .env key and rerun with --resume.", flush=True)
            break
        write_jsonl(jsonl_path, record)
        rewrite_csv(csv_path, jsonl_path)
        print(
            json.dumps(
                {
                    "index": index,
                    "status": record.get("status"),
                    "pass": record.get("pass"),
                    "failure": eval_chat.failure_summary(record),
                    "durationSeconds": record.get("durationSeconds"),
                    "allAgentsCalled": record.get("allAgentsCalled"),
                    "engineerLoop": record.get("engineerLoop"),
                    "allRequiredMarkersFound": record.get("allRequiredMarkersFound"),
                    "missingMarkers": record.get("missingMarkers"),
                    "officialEvaluation": record.get("officialEvaluation"),
                    "summaryJson": record.get("summaryJson"),
                    "generatedSourceDir": record.get("generatedSourceDir"),
                },
                indent=2,
                ensure_ascii=False,
            ),
            flush=True,
        )
    summary = write_summary(output_dir, jsonl_path, csv_path)
    print(json.dumps(summary, indent=2), flush=True)
    return 0 if summary["failed"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
