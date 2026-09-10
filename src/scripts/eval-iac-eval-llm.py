#!/usr/bin/env python3
"""Run a single-LLM IaC-Eval baseline using the official eval.py prompt shape."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from openai import OpenAI


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
EVAL_PATH = SCRIPT_DIR / "eval-iac-eval-chat.py"
AGENT_DIR = ROOT / "agent"
DEFAULT_OFFICIAL_REPO = Path("/private/tmp/iac-eval-official")
DELIMITERS = ["```hcl", "```json", "```HCL", "```Terraform", "```terraform", "```"]

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


def official_system_prompt(official_repo: Path) -> str:
    prompt_path = official_repo / "evaluation" / "prompt-templates" / "system-prompt.txt"
    if prompt_path.is_file():
        return prompt_path.read_text(encoding="utf-8").strip()
    return (
        "You are TerraformAI, an AI agent that builds and deploys Cloud Infrastructure written in Terraform HCL. "
        "Generate a description of the Terraform program you will define, followed by a single Terraform HCL program "
        "in response to each of my Instructions. Make sure the configuration is deployable. Create IAM roles as needed. "
        "If variables are used, make sure default values are supplied. Be sure to include a valid provider configuration "
        "within a valid region. Make sure there are no undeclared resources (e.g., as references) or variables, that is, "
        "all resources and variables needed in the configuration should be fully specified."
    )


def official_user_prompt(row: dict[str, str], official_repo: Path, prompt_strategy: str) -> str:
    prompt = eval_chat.clean(row.get("Prompt"))
    if prompt_strategy == "default":
        return "Here is the actual prompt: " + prompt
    template_name = {"cot": "CoT.txt", "few-shot": "few-shot.txt"}[prompt_strategy]
    template_path = official_repo / "evaluation" / "prompt-templates" / template_name
    template = template_path.read_text(encoding="utf-8")
    return template + prompt


def separate_answer_and_code(text: str) -> tuple[str, str]:
    answer = str(text or "").strip()
    code = ""
    for delimiter in DELIMITERS:
        parts = str(text or "").split(delimiter)
        if len(parts) < 2:
            continue
        answer = parts[0].strip()
        code = parts[1].strip().rsplit("```", 1)[0].strip()
        if code:
            return answer, code
    return answer, code


def load_completed_indices(jsonl_path: Path, include_failures: bool = True) -> set[int]:
    done: set[int] = set()
    if not jsonl_path.exists():
        return done
    with jsonl_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            index = item.get("index")
            if not isinstance(index, int):
                continue
            if item.get("status") == "error":
                continue
            if include_failures or item.get("pass"):
                done.add(index)
    return done


def load_indices_from_jsonl(jsonl_path: Path) -> list[int]:
    if not jsonl_path.exists():
        raise FileNotFoundError(f"Local result JSONL not found: {jsonl_path}")
    indices: list[int] = []
    seen: set[int] = set()
    with jsonl_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            index = item.get("index")
            if isinstance(index, int) and index not in seen:
                seen.add(index)
                indices.append(index)
    return indices


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, default=str), encoding="utf-8")


def write_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")


def rewrite_csv(csv_path: Path, jsonl_path: Path) -> None:
    rows: list[dict[str, Any]] = []
    if jsonl_path.exists():
        with jsonl_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                if not line.strip():
                    continue
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
        "avgBleuScore": sum(float(record.get("bleuScore") or 0) for record in records) / len(records) if records else 0,
        "jsonl": str(jsonl_path),
        "csv": str(csv_path),
    }
    write_json(output_dir / "summary.json", summary)
    return summary


def create_client() -> tuple[OpenAI, str]:
    credentials = local_runner.get_local_openai_credentials()
    client = OpenAI(api_key=credentials["api_key"], base_url=credentials["base_url"])
    return client, credentials["model_id"]


def call_llm(client: OpenAI, model_id: str, system_prompt: str, user_prompt: str) -> str:
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            response = client.chat.completions.create(
                model=model_id,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
            )
            return response.choices[0].message.content or ""
        except Exception as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(5 * (attempt + 1))
    assert last_error is not None
    raise last_error


def is_auth_error(record: dict[str, Any]) -> bool:
    text = json.dumps(record, ensure_ascii=False)
    return "INVALID_API_KEY" in text or "authentication_error" in text or "AuthenticationError" in text


def is_transient_model_error(record: dict[str, Any]) -> bool:
    if record.get("status") != "error":
        return False
    text = json.dumps(record, ensure_ascii=False)
    return (
        "Expecting value: line 1 column 1" in text
        or "APIConnectionError" in text
        or "APITimeoutError" in text
        or "RemoteProtocolError" in text
    )


def build_record(
    row: dict[str, str],
    index: int,
    output_dir: Path,
    client: OpenAI,
    model_id: str,
    system_prompt: str,
    official_repo: Path,
    prompt_strategy: str,
    official_eval: bool,
    terraform_bin: str,
    opa_bin: str,
    official_timeout: int,
    terraform_plugin_cache_dir: str,
) -> dict[str, Any]:
    started = time.time()
    session_id = f"llm-{uuid.uuid4().hex[:12]}"
    source_dir = output_dir / "generated-source" / f"row-{index:04d}-{session_id}"
    summary_path = output_dir / "run-summaries" / f"row-{index:04d}-{session_id}.json"
    source_dir.mkdir(parents=True, exist_ok=True)
    markers = eval_chat.required_markers_for_row(row)
    try:
        user_prompt = official_user_prompt(row, official_repo, prompt_strategy)
        raw = call_llm(client, model_id, system_prompt, user_prompt)
        answer, code = separate_answer_and_code(raw)
        (source_dir / "main.tf").write_text(code, encoding="utf-8")
        reference_output = eval_chat.clean(row.get("Reference output") or row.get("Reference Output"))
        marker_results = {marker: marker in raw or marker in code for marker in markers}
        missing_markers = [marker for marker, found in marker_results.items() if not found]
        file_contents = {"main.tf": code} if code else {}
        artifact_quality = eval_chat.artifact_quality_check(source_dir, file_contents)
        official = eval_chat.run_official_iac_eval(
            source_dir,
            eval_chat.rego_policy_for_row(row),
            official_eval,
            terraform_bin,
            opa_bin,
            official_timeout,
            None,
        )
        passed = bool(code.strip())
        if official_eval:
            passed = bool(passed and official.get("officialPass"))
        else:
            passed = bool(passed and all(marker_results.values()))
        record = {
            "index": index,
            "rowId": eval_chat.row_id(index, row),
            "status": "completed",
            "pass": passed,
            "stack": "llm-only",
            "region": "local",
            "agentSet": "llm-only",
            "sessionId": session_id,
            "userId": "local-user",
            "durationSeconds": round(time.time() - started, 2),
            "difficulty": eval_chat.clean(row.get("Difficulty")),
            "resource": eval_chat.clean(row.get("Resource")),
            "prompt": eval_chat.clean(row.get("Prompt")),
            "intent": eval_chat.clean(row.get("Intent")),
            "referenceOutput": reference_output,
            "bleuScore": round(eval_chat.bleu_score(reference_output, code), 6),
            "eventCount": 1,
            "toolNames": ["gpt5.5"],
            "toolCallSequence": ["gpt5.5"],
            "engineerLoop": {"engineerCallCount": 0, "verificationCallCount": 0, "engineerAfterVerifier": False, "engineerAfterReviewer": False},
            "allAgentsCalled": True,
            "specialistProgress": {"startedAgents": ["gpt5.5"], "completedAgents": ["gpt5.5"], "missingAgents": []},
            "terraformFiles": ["main.tf"] if code else [],
            "generatedSourceDir": str(source_dir),
            "generatedSourceFiles": ["generated-source/" + source_dir.name + "/main.tf"] if code else [],
            "artifactQuality": artifact_quality,
            "officialEvaluation": official,
            "requiredMarkers": marker_results,
            "missingMarkers": missing_markers,
            "allRequiredMarkersFound": all(marker_results.values()),
            "responsePreview": raw[:1200],
            "summaryJson": str(summary_path),
            "llmOnly": True,
            "modelId": model_id,
            "officialSystemPrompt": system_prompt,
            "officialUserPrompt": user_prompt,
            "promptStrategy": prompt_strategy,
            "answer": answer,
        }
        failure = eval_chat.failure_summary(record)
        record["failure_category"] = failure["failureCategory"]
        record["failure_reason"] = failure["failureReason"]
        write_json(summary_path, record)
        return record
    except Exception as exc:
        record = {
            "index": index,
            "rowId": eval_chat.row_id(index, row),
            "status": "error",
            "pass": False,
            "stack": "llm-only",
            "region": "local",
            "agentSet": "llm-only",
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
            "llmOnly": True,
            "modelId": model_id,
        }
        failure = eval_chat.failure_summary(record)
        record["failure_category"] = failure["failureCategory"]
        record["failure_reason"] = failure["failureReason"]
        write_json(summary_path, record)
        return record


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-file", default="")
    parser.add_argument("--dataset-url", default=eval_chat.DEFAULT_DATASET_URL)
    parser.add_argument("--output-dir", default="eval-results/iac-eval-llm-gpt55")
    parser.add_argument("--env-file", default=".env")
    parser.add_argument("--official-repo", default=str(DEFAULT_OFFICIAL_REPO))
    parser.add_argument("--prompt-strategy", choices=("default", "cot", "few-shot"), default="default")
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--limit", type=int, default=3)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--confirm-cost", action="store_true")
    parser.add_argument("--indices-file", default="")
    parser.add_argument("--match-local-jsonl", default="", help="Run the indexes currently present in a multi-agent local JSONL result file.")
    parser.add_argument("--official-eval", action="store_true")
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
    client, model_id = create_client()
    rows = eval_chat.load_dataset_rows(args.dataset_file or None, args.dataset_url)
    selected = list(enumerate(rows))
    indices = eval_chat.load_indices(args.indices_file)
    if args.match_local_jsonl:
        indices.update(load_indices_from_jsonl(Path(args.match_local_jsonl)))
    if indices:
        selected = [(index, row) for index, row in selected if index in indices]
    if args.start:
        selected = [(index, row) for index, row in selected if index >= args.start]
    if not args.full and not indices:
        selected = selected[: args.limit]

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = output_dir / "iac_eval_llm_results.jsonl"
    csv_path = output_dir / "iac_eval_llm_results.csv"
    done = load_completed_indices(jsonl_path) if args.resume else set()
    system_prompt = official_system_prompt(Path(args.official_repo))

    print(
        json.dumps(
            {
                "selectedRows": len(selected),
                "loadedEnvKeys": loaded_keys,
                "outputDir": str(output_dir),
                "modelId": model_id,
                "officialRepo": str(Path(args.official_repo)),
                "promptSetup": f"official iac-eval system prompt + {args.prompt_strategy} prompt enhancement",
            },
            indent=2,
        ),
        flush=True,
    )
    for index, row in selected:
        if index in done:
            print(f"Skipping completed LLM-only IaC-Eval row {index}", flush=True)
            continue
        print(f"Running LLM-only IaC-Eval row {index}: difficulty={eval_chat.clean(row.get('Difficulty'))} resource={eval_chat.clean(row.get('Resource'))[:120]}", flush=True)
        record = build_record(
            row,
            index,
            output_dir,
            client,
            model_id,
            system_prompt,
            Path(args.official_repo),
            args.prompt_strategy,
            args.official_eval,
            args.terraform_bin,
            args.opa_bin,
            args.official_timeout,
            args.terraform_plugin_cache_dir,
        )
        if is_auth_error(record):
            print("Stopping after model authentication error. Fix .env and rerun with --resume.", flush=True)
            break
        if is_transient_model_error(record):
            print("Stopping after transient model endpoint error. Rerun with --resume after the endpoint recovers.", flush=True)
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
