#!/usr/bin/env python3
"""Evaluate the deployed chat multi-agent pipeline on IaC-Eval rows.

This runner is intentionally resumable because the full dataset is long-running
and expensive. It writes one JSONL record per row and a spreadsheet-friendly CSV
summary after every row.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import uuid
import zipfile
from pathlib import Path
from typing import Any

from nltk.translate.bleu_score import SmoothingFunction, corpus_bleu


ROOT = Path(__file__).resolve().parent
SMOKE_PATH = ROOT / "smoke-iac-eval-chat.py"
DEFAULT_DATASET_URL = "https://huggingface.co/datasets/autoiac-project/iac-eval/resolve/main/data.csv"
AGENT_NAMES = [
    "architect_agent",
    "engineer_agent",
    "reviewer_agent",
    "security_prover_agent",
    "cost_capacity_agent",
    "devops_agent",
]
DEFAULT_TERRAFORM_PLUGIN_CACHE_DIR = Path.home() / ".terraform.d" / "plugin-cache"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def load_smoke_module():
    spec = importlib.util.spec_from_file_location("iac_eval_smoke", SMOKE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SMOKE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


smoke = load_smoke_module()


def read_text_url(url: str) -> str:
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read().decode("utf-8", "replace")


def load_dataset_rows(dataset_file: str | None, dataset_url: str) -> list[dict[str, str]]:
    if dataset_file:
        text = Path(dataset_file).read_text(encoding="utf-8")
        return list(csv.DictReader(text.splitlines()))
    try:
        from datasets import load_dataset

        dataset = load_dataset("autoiac-project/iac-eval", split="test")
        return [dict(row) for row in dataset]
    except Exception:
        text = read_text_url(dataset_url)
        return list(csv.DictReader(text.splitlines()))


def load_indices(path: str) -> set[int]:
    if not path:
        return set()
    text = Path(path).read_text(encoding="utf-8")
    indices: set[int] = set()
    for token in re.split(r"[\s,]+", text):
        token = token.strip()
        if not token:
            continue
        indices.add(int(token))
    return indices


def clean(value: Any) -> str:
    return str(value or "").strip()


def truncate(value: str, limit: int = 4000) -> str:
    value = str(value or "")
    if len(value) <= limit:
        return value
    return value[:limit] + f"... <truncated {len(value) - limit} chars>"


def row_id(index: int, row: dict[str, str]) -> str:
    return clean(row.get("id") or row.get("ID") or row.get("task_id") or row.get("Task ID") or index)


def build_prompt(row: dict[str, str]) -> str:
    resource = clean(row.get("Resource"))
    prompt = clean(row.get("Prompt"))
    difficulty = clean(row.get("Difficulty"))
    intent = clean(row.get("Intent"))
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

Multi-agent workflow I want to test:
1. Architect: identify the required AWS resources, dependencies, and resource graph.
2. Engineer: write the Terraform/OpenTofu files.
3. Reviewer: check correctness against the benchmark prompt and likely Rego intent.
4. Security: check IAM, public exposure, encryption, and unsafe defaults.
5. Cost/capacity: identify cost or quota risks.
6. DevOps: run or propose validation commands such as terraform fmt, terraform validate, policy scan, and plan-safe checks.
7. If reviewer, security, cost/capacity, or DevOps returns a finding that requires Terraform/file changes, send the finding back to Engineer, have Engineer update the files, then rerun the relevant verification agent before finalizing. Limit Engineer to at most 3 total implementation/fix passes for this benchmark row; after 3 Engineer calls, stop fixing and finalize with the remaining findings.

Return changed files, validation commands/results, agent findings, whether Engineer was recalled after verification findings, and final Terraform summary."""


def split_resource_markers(resource: str) -> list[str]:
    markers: list[str] = []
    for part in re.split(r"[,;\s]+", resource):
        token = part.strip().strip('"`')
        if token.startswith(("aws_", "data.aws_")) and token not in markers:
            markers.append(token)
    return markers


def intent_markers(intent: str, limit: int = 18) -> list[str]:
    markers: list[str] = []
    for quoted in re.findall(r'"([^"]{3,120})"', intent):
        if quoted.startswith(("aws_", "logs:", "ec2:", "s3:", "iam:", "lambda:", "route53:", "cloudwatch:")):
            if quoted not in markers:
                markers.append(quoted)
    return markers[:limit]


def required_markers_for_row(row: dict[str, str]) -> list[str]:
    markers = split_resource_markers(clean(row.get("Resource")))
    for marker in intent_markers(clean(row.get("Intent"))):
        if marker not in markers:
            markers.append(marker)
    return markers


def bleu_score(reference: str, candidate: str) -> float:
    reference_tokens = reference.split()
    candidate_tokens = candidate.split()
    if len(reference_tokens) < 4 or len(candidate_tokens) < 4:
        return 0.0
    return float(
        corpus_bleu(
            [[reference_tokens]],
            [candidate_tokens],
            weights=(0.25, 0.25, 0.25, 0.25),
            smoothing_function=SmoothingFunction().method3,
        )
    )


def concise_failure_text(value: str, limit: int = 500) -> str:
    value = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(value) <= limit:
        return value
    return value[:limit] + f"... <truncated {len(value) - limit} chars>"


def failure_summary(record: dict[str, Any]) -> dict[str, str]:
    if record.get("pass"):
        return {"failureCategory": "", "failureReason": ""}
    if record.get("status") == "error":
        return {"failureCategory": "runtime_error", "failureReason": concise_failure_text(record.get("error", ""))}
    if not record.get("allAgentsCalled"):
        return {"failureCategory": "agent_workflow", "failureReason": "Not all required specialist agents were called."}
    artifact = record.get("artifactQuality") or {}
    if not artifact.get("artifactCompletePass", True):
        return {
            "failureCategory": "artifact_incomplete",
            "failureReason": "Missing local files: " + ", ".join(artifact.get("missingPathModuleFiles") or []),
        }
    official = record.get("officialEvaluation") or {}
    official_error = official.get("terraformPlanError") or official.get("opaEvaluationError") or official.get("notes") or ""
    if official.get("terraformPlanSuccess") is False:
        return {"failureCategory": "terraform_plan", "failureReason": concise_failure_text(official_error)}
    if official.get("opaEvaluationResult") == "Error":
        reason = "OPA evaluation error"
        if any(token in official_error for token in ("rego_parse_error", "rego_unsafe_var_error", "unexpected identifier token", "var falsedefault is unsafe")):
            reason = "OPA policy parse/compile error from dataset Rego intent"
        return {"failureCategory": "opa_error", "failureReason": concise_failure_text(reason + ": " + official_error)}
    if official.get("opaEvaluationResult") == "Failure":
        return {"failureCategory": "opa_rule_failure", "failureReason": concise_failure_text(official_error)}
    if official.get("officialPass") is False:
        return {"failureCategory": "official_eval", "failureReason": concise_failure_text(official_error)}
    if not record.get("allRequiredMarkersFound"):
        return {"failureCategory": "marker_mismatch", "failureReason": "Missing markers: " + ", ".join(record.get("missingMarkers") or [])}
    return {"failureCategory": "unknown", "failureReason": "Row failed without a classified reason."}


def rego_policy_for_row(row: dict[str, str]) -> str:
    return clean(row.get("Rego intent") or row.get("Rego Intent") or row.get("rego_intent"))


def normalize_rego_policy(policy: str) -> str:
    """Restore line breaks in IaC-Eval CSV Rego policies when they are minified."""
    if not policy:
        return ""
    policy = policy.replace("\r\n", "\n").replace("\r", "\n")
    if "\n" in policy and "falsedefault" not in policy and "mainimport" not in policy:
        return policy.strip() + "\n"

    policy = re.sub(r"package\s+([A-Za-z0-9_.]+?)import\s+", r"package \1\nimport ", policy)
    policy = re.sub(r"(import\s+future\.keywords\.in)default\s+", r"\1\ndefault ", policy)
    policy = re.sub(r"(=\s*(?:true|false))(?=default\b)", r"\1\n", policy)

    decl_pattern = re.compile(
        r"(?:allow|is_[A-Za-z_]\w*|has_[A-Za-z_]\w*|valid_[A-Za-z_]\w*|"
        r"dynamodb_[A-Za-z_]\w*|ttl_[A-Za-z_]\w*|stream_[A-Za-z_]\w*|"
        r"encryption_[A-Za-z_]\w*|requirement\d*|[A-Za-z_]\w*_starts_with)(?:\([^)]*\))?\s*\{"
    )
    while "#" in policy:
        start = policy.index("#")
        match = decl_pattern.search(policy, start)
        close = policy.find("}", start)
        resume_at = None
        if match:
            resume_at = match.start()
        if close != -1 and (resume_at is None or close < resume_at):
            resume_at = close
        if resume_at is None:
            policy = policy[:start]
            break
        policy = policy[:start] + policy[resume_at:]

    rule_names = sorted(
        {
            match.group(1)
            for match in re.finditer(r"\b([A-Za-z_]\w*)\s*(?:\([^)]*\))?\s*\{", policy)
            if match.group(1) not in {"if", "else", "some"}
        },
        key=len,
        reverse=True,
    )
    if rule_names:
        names = "|".join(re.escape(name) for name in rule_names)
        policy = re.sub(rf"(?<![\n\s{{}}])({names})(?=\s*(?:\(|\{{))", r"\n\1", policy)
        policy = re.sub(rf"(?<![\n\s{{}}])({names})(?=\()", r"\n\1", policy)

    policy = re.sub(r"(?<![\n\s{])default\s+", r"\ndefault ", policy)
    policy = re.sub(r"(?<![\n\s{])some\s+", r"\nsome ", policy)
    policy = re.sub(r"(?<![\n\s{])(resource\d*\.)", r"\n\1", policy)
    policy = re.sub(r"(?<![\n\s{])(input\.)", r"\n\1", policy)
    policy = re.sub(r"(=\s*(?:true|false))(?=[A-Za-z_])", r"\1\n", policy)
    policy = re.sub(r"(==\s*(?:true|false))(?=[A-Za-z_])", r"\1\n", policy)
    policy = policy.replace("{", "{\n").replace("}", "\n}\n")
    policy = policy.replace("\t", "    ")
    policy = re.sub(r" {2,}", "\n", policy)

    kept_lines: list[str] = []
    for line in policy.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        match = decl_pattern.search(stripped)
        if match and match.start() > 0 and not re.search(r"(==|:=|!=)", stripped[: match.start()]):
            stripped = stripped[match.start() :]
        if not stripped.startswith(("package ", "import ", "some ")) and re.match(r"^[a-z][a-z ;,'-]+$", stripped):
            continue
        kept_lines.append(stripped)
    policy = "\n".join(kept_lines)
    policy = re.sub(r"\n{2,}", "\n", policy)
    return policy.strip() + "\n"


def bool_leaves(value: Any) -> list[bool]:
    if isinstance(value, bool):
        return [value]
    if isinstance(value, dict):
        leaves: list[bool] = []
        for item in value.values():
            leaves.extend(bool_leaves(item))
        return leaves
    if isinstance(value, list):
        leaves: list[bool] = []
        for item in value:
            leaves.extend(bool_leaves(item))
        return leaves
    return []


def artifact_quality_check(source_path: Path, file_contents: dict[str, str]) -> dict[str, Any]:
    combined = "\n\n".join(file_contents.values())
    path_refs = sorted(set(re.findall(r"\$\{path\.module\}/([^\"}]+)", combined)))
    missing_path_refs = [ref for ref in path_refs if not (source_path / ref).exists()]
    findings: list[dict[str, str]] = []
    for key, content in file_contents.items():
        for lineno, line in enumerate(content.splitlines(), start=1):
            stripped = line.strip()
            if 'cidr_blocks = ["0.0.0.0/0"]' in stripped:
                findings.append({"severity": "high", "file": key, "line": str(lineno), "finding": "broad_ingress_or_egress_cidr"})
            if "publicly_accessible" in stripped and "true" in stripped:
                findings.append({"severity": "high", "file": key, "line": str(lineno), "finding": "public_rds_instance"})
            if "skip_final_snapshot" in stripped and "true" in stripped:
                findings.append({"severity": "medium", "file": key, "line": str(lineno), "finding": "rds_final_snapshot_disabled"})
            if re.search(r'password\s*=\s*"[^"]+"', stripped, re.IGNORECASE):
                findings.append({"severity": "high", "file": key, "line": str(lineno), "finding": "hardcoded_password"})
    for ref in missing_path_refs:
        findings.append({"severity": "high", "file": ref, "line": "", "finding": "missing_path_module_file"})
    return {
        "artifactCompletePass": not missing_path_refs,
        "missingPathModuleFiles": missing_path_refs,
        "qualityFindings": findings,
        "qualityGatePass": not findings,
    }


def variable_blocks(source_path: Path) -> dict[str, str]:
    blocks: dict[str, str] = {}
    for tf_file in source_path.rglob("*.tf"):
        text = tf_file.read_text(encoding="utf-8", errors="replace")
        for match in re.finditer(r'variable\s+"([^"]+)"\s*\{', text):
            name = match.group(1)
            start = match.end()
            depth = 1
            pos = start
            while pos < len(text) and depth:
                if text[pos] == "{":
                    depth += 1
                elif text[pos] == "}":
                    depth -= 1
                pos += 1
            blocks[name] = text[start : pos - 1]
    return blocks


def hcl_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(hcl_value(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{key} = {hcl_value(item)}" for key, item in value.items()) + " }"
    return json.dumps(str(value))


def default_variable_value(name: str, block: str) -> Any:
    lowered = name.lower()
    block_lower = block.lower()
    if "password" in lowered:
        return "Password123456789!"
    if "username" in lowered or "user_name" in lowered:
        return "admin"
    if "cidr" in lowered:
        return "10.0.0.0/16"
    if "availability_zone" in lowered:
        return "us-east-1a"
    if "region" in lowered:
        return "us-east-1"
    if "instance_class" in lowered:
        return "db.t3.micro"
    if "engine" in lowered:
        return "postgres"
    if "bucket" in lowered:
        return "iac-eval-placeholder-bucket"
    if "name" in lowered or "identifier" in lowered:
        return "iac-eval"
    if "list(" in block_lower or block_lower.startswith("list") or "set(" in block_lower:
        return ["iac-eval"]
    if "map(" in block_lower or block_lower.startswith("map"):
        return {"Name": "iac-eval"}
    if "bool" in block_lower:
        return False
    if "number" in block_lower:
        return 1
    return "iac-eval"


def write_default_inputs(source_path: Path) -> list[str]:
    values: dict[str, Any] = {}
    for name, block in variable_blocks(source_path).items():
        if re.search(r"(^|\n)\s*default\s*=", block):
            continue
        values[name] = default_variable_value(name, block)
    if not values:
        return []
    tfvars_path = source_path / "terraform.tfvars"
    tfvars_path.write_text(
        "\n".join(f"{name} = {hcl_value(value)}" for name, value in sorted(values.items())) + "\n",
        encoding="utf-8",
    )
    return [str(tfvars_path.name)]


def create_missing_module_files(source_path: Path) -> list[str]:
    combined = "\n\n".join(path.read_text(encoding="utf-8", errors="replace") for path in source_path.rglob("*.tf"))
    created: list[str] = []
    for ref in sorted(set(re.findall(r"\$\{path\.module\}/([^\"}]+)", combined))):
        target = (source_path / ref).resolve()
        if source_path.resolve() not in target.parents:
            continue
        if target.exists():
            continue
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
        except FileExistsError:
            continue
        if target.suffix == ".zip":
            with zipfile.ZipFile(target, "w") as archive:
                archive.writestr("README.txt", "placeholder bundle for official IaC-Eval plan-only recheck\n")
        else:
            target.write_text("placeholder for official IaC-Eval plan-only recheck\n", encoding="utf-8")
        created.append(str(target.relative_to(source_path)))
    return created


def prepare_official_eval_workspace(source_path: Path) -> dict[str, list[str]]:
    return {
        "defaultInputFiles": write_default_inputs(source_path),
        "createdMissingFiles": create_missing_module_files(source_path),
    }


def terraform_env(plugin_cache_dir: str | None, tmp_dir: str | None = None) -> dict[str, str] | None:
    if not plugin_cache_dir and not tmp_dir:
        return None
    env = dict(__import__("os").environ)
    if plugin_cache_dir:
        cache_dir = Path(plugin_cache_dir).expanduser()
        cache_dir.mkdir(parents=True, exist_ok=True)
        env["TF_PLUGIN_CACHE_DIR"] = str(cache_dir)
        cli_config = cache_dir.parent / "rc" / "terraformrc"
        cli_config.parent.mkdir(parents=True, exist_ok=True)
        cli_config.write_text(f'plugin_cache_dir = "{cache_dir}"\n', encoding="utf-8")
        env["TF_CLI_CONFIG_FILE"] = str(cli_config)
    if tmp_dir:
        resolved_tmp_dir = Path(tmp_dir).expanduser()
        resolved_tmp_dir.mkdir(parents=True, exist_ok=True)
        env["TMPDIR"] = str(resolved_tmp_dir)
    return env


def run_command(args: list[str], cwd: Path, timeout: int, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)


def opa_uses_rego_v1_by_default(opa_bin: str, timeout: int) -> bool:
    try:
        version = subprocess.run([opa_bin, "version"], capture_output=True, text=True, timeout=timeout)
    except Exception:
        return False
    return "Rego Version: v1" in (version.stdout or version.stderr)


def run_official_iac_eval(
    source_path: Path,
    policy_file: str,
    enabled: bool,
    terraform_bin: str,
    opa_bin: str,
    timeout: int,
    plugin_cache_dir: str | None = str(DEFAULT_TERRAFORM_PLUGIN_CACHE_DIR),
    plugin_cache_cleanup_dir: str | None = None,
    terraform_tmp_dir: str | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "enabled": enabled,
        "terraformPlanSuccess": None,
        "terraformPlanError": "",
        "opaEvaluationResult": "",
        "opaEvaluationError": "",
        "officialPass": None,
        "notes": "",
        "defaultInputFiles": [],
        "createdMissingFiles": [],
    }
    if not enabled:
        result["notes"] = "Skipped. Pass --official-eval to run Terraform plan plus OPA/Rego evaluation."
        return result
    if not policy_file:
        result["terraformPlanSuccess"] = False
        result["officialPass"] = False
        result["notes"] = "Skipped official evaluation because this row has no Rego intent policy."
        return result
    if shutil.which(terraform_bin) is None:
        result["terraformPlanSuccess"] = False
        result["officialPass"] = False
        result["terraformPlanError"] = f"Terraform binary not found: {terraform_bin}"
        return result
    if shutil.which(opa_bin) is None:
        result["terraformPlanSuccess"] = False
        result["officialPass"] = False
        result["opaEvaluationError"] = f"OPA binary not found: {opa_bin}"
        return result

    work_dir = source_path.parent / f".official-eval-{source_path.name}"
    if work_dir.exists():
        shutil.rmtree(work_dir)
    shutil.copytree(source_path, work_dir)
    prepared = prepare_official_eval_workspace(work_dir)
    result["defaultInputFiles"] = prepared["defaultInputFiles"]
    result["createdMissingFiles"] = prepared["createdMissingFiles"]
    policy_path = work_dir / "policy.rego"
    policy_path.write_text(policy_file, encoding="utf-8")
    row_plugin_cache_dir = plugin_cache_dir
    if row_plugin_cache_dir is None:
        row_plugin_cache_dir = str(work_dir / ".terraform-plugin-cache")
    tf_env = terraform_env(row_plugin_cache_dir, terraform_tmp_dir)
    try:
        init = run_command([terraform_bin, "init", "-input=false", "-no-color"], work_dir, timeout, tf_env)
        if init.returncode != 0:
            result["terraformPlanSuccess"] = False
            result["officialPass"] = False
            result["terraformPlanError"] = truncate(init.stderr or init.stdout)
            return result
        plan = run_command([terraform_bin, "plan", "-out", "plan.out", "-no-color", "-input=false", "-lock=false"], work_dir, timeout, tf_env)
        result["terraformPlanSuccess"] = plan.returncode == 0
        if plan.returncode != 0:
            result["officialPass"] = False
            result["terraformPlanError"] = truncate(plan.stderr or plan.stdout)
            return result
        with (work_dir / "plan.json").open("w", encoding="utf-8") as handle:
            show = subprocess.run([terraform_bin, "show", "-json", "plan.out"], cwd=work_dir, stdout=handle, stderr=subprocess.PIPE, text=True, timeout=timeout, env=tf_env)
        if show.returncode != 0:
            result["officialPass"] = False
            result["opaEvaluationError"] = truncate(show.stderr)
            return result
        opa_args = [opa_bin, "eval", "-i", "plan.json", "-d", "policy.rego", "data"]
        if "import rego.v1" in policy_file:
            opa_args.insert(2, "--v1-compatible")
        elif opa_uses_rego_v1_by_default(opa_bin, timeout):
            opa_args.insert(2, "--v0-compatible")
        opa = run_command(opa_args, work_dir, timeout)
        if opa.returncode != 0:
            result["opaEvaluationResult"] = "Error"
            result["opaEvaluationError"] = truncate(opa.stderr or opa.stdout)
            result["officialPass"] = False
            return result
        parsed = json.loads(opa.stdout)
        value = parsed["result"][0]["expressions"][0]["value"]
        leaves = bool_leaves(value)
        opa_success = bool(leaves) and False not in leaves
        result["opaEvaluationResult"] = "Success" if opa_success else "Failure"
        result["opaEvaluationError"] = "" if opa_success else truncate(json.dumps(parsed, ensure_ascii=False))
        result["officialPass"] = bool(result["terraformPlanSuccess"] and opa_success)
        return result
    except Exception as exc:
        result["officialPass"] = False
        result["opaEvaluationError"] = truncate(str(exc))
        return result
    finally:
        if work_dir.exists():
            shutil.rmtree(work_dir, ignore_errors=True)
        if plugin_cache_cleanup_dir:
            cleanup_dir = Path(plugin_cache_cleanup_dir).expanduser().resolve()
            if cleanup_dir.exists():
                shutil.rmtree(cleanup_dir, ignore_errors=True)


def completed_indices(jsonl_path: Path) -> set[int]:
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
            if isinstance(index, int):
                done.add(index)
    return done


def write_jsonl(jsonl_path: Path, record: dict[str, Any]) -> None:
    with jsonl_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")


def write_generated_source(
    source_dir: Path,
    row_index: int,
    session_id: str,
    terraform_files: list[str],
    file_contents: dict[str, str],
    metadata: dict[str, Any],
) -> dict[str, Any]:
    resolved_source_dir = source_dir.resolve()
    row_dir = resolved_source_dir / f"row-{row_index:04d}-{session_id}"
    row_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []
    for key in terraform_files:
        content = file_contents.get(key, "")
        if not content:
            continue
        target = (row_dir / key).resolve()
        if row_dir not in target.parents and target != row_dir:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        written.append(str(target.relative_to(resolved_source_dir)))
    metadata_path = row_dir / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    written.append(str(metadata_path.relative_to(resolved_source_dir)))
    return {
        "sourceDir": str(row_dir),
        "sourceFiles": written,
    }


def flatten_for_sheet(record: dict[str, Any]) -> dict[str, Any]:
    marker_results = record.get("requiredMarkers") if isinstance(record.get("requiredMarkers"), dict) else {}
    progress = record.get("specialistProgress") if isinstance(record.get("specialistProgress"), dict) else {}
    response_preview = re.sub(r"\s+", " ", str(record.get("responsePreview", ""))).strip()
    failure = failure_summary(record)
    return {
        "index": record.get("index"),
        "row_id": record.get("rowId"),
        "status": record.get("status"),
        "pass": record.get("pass"),
        "failure_category": failure["failureCategory"],
        "failure_reason": failure["failureReason"],
        "duration_seconds": record.get("durationSeconds"),
        "session_id": record.get("sessionId"),
        "difficulty": record.get("difficulty"),
        "resource": record.get("resource"),
        "prompt": record.get("prompt"),
        "intent": record.get("intent"),
        "bleu_score": record.get("bleuScore", ""),
        "agents_called": ", ".join(record.get("toolNames") or []),
        "tool_call_sequence": " -> ".join(record.get("toolCallSequence") or []),
        "all_agents_called": record.get("allAgentsCalled"),
        "engineer_call_count": (record.get("engineerLoop") or {}).get("engineerCallCount", ""),
        "engineer_after_reviewer": (record.get("engineerLoop") or {}).get("engineerAfterReviewer", ""),
        "engineer_after_verifier": (record.get("engineerLoop") or {}).get("engineerAfterVerifier", ""),
        "terraform_files": ", ".join(record.get("terraformFiles") or []),
        "generated_source_dir": record.get("generatedSourceDir", ""),
        "generated_source_files": ", ".join(record.get("generatedSourceFiles") or []),
        "artifact_complete_pass": (record.get("artifactQuality") or {}).get("artifactCompletePass", ""),
        "artifact_missing_files": ", ".join((record.get("artifactQuality") or {}).get("missingPathModuleFiles") or []),
        "quality_gate_pass": (record.get("artifactQuality") or {}).get("qualityGatePass", ""),
        "quality_findings_json": json.dumps((record.get("artifactQuality") or {}).get("qualityFindings") or [], ensure_ascii=False, sort_keys=True),
        "official_eval_enabled": (record.get("officialEvaluation") or {}).get("enabled", ""),
        "official_plan_success": (record.get("officialEvaluation") or {}).get("terraformPlanSuccess", ""),
        "official_opa_result": (record.get("officialEvaluation") or {}).get("opaEvaluationResult", ""),
        "official_pass": (record.get("officialEvaluation") or {}).get("officialPass", ""),
        "official_error": (record.get("officialEvaluation") or {}).get("terraformPlanError", "") or (record.get("officialEvaluation") or {}).get("opaEvaluationError", ""),
        "required_marker_count": len(marker_results),
        "found_marker_count": sum(1 for value in marker_results.values() if value),
        "all_required_markers_found": record.get("allRequiredMarkersFound"),
        "required_markers": ", ".join(marker_results.keys()),
        "missing_markers": ", ".join(record.get("missingMarkers") or []),
        "marker_results_json": json.dumps(marker_results, ensure_ascii=False, sort_keys=True),
        "event_count": record.get("eventCount"),
        "started_agents": ", ".join(progress.get("startedAgents") or []),
        "completed_agents": ", ".join(progress.get("completedAgents") or []),
        "error": record.get("error", ""),
        "response_preview": response_preview,
    }


def rewrite_csv(csv_path: Path, jsonl_path: Path) -> None:
    rows: list[dict[str, Any]] = []
    if jsonl_path.exists():
        with jsonl_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    rows.append(flatten_for_sheet(json.loads(line)))
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


def run_one(
    row: dict[str, str],
    index: int,
    stack: dict[str, Any],
    auth: dict[str, str],
    runtime_arn: str,
    source_dir: Path,
    official_eval: bool,
    terraform_bin: str,
    opa_bin: str,
    official_timeout: int,
    terraform_plugin_cache_dir: str,
) -> dict[str, Any]:
    region = stack["region"]
    session_id = str(uuid.uuid4())
    started = time.time()
    markers = required_markers_for_row(row)
    try:
        events = smoke.invoke_runtime(
            runtime_arn,
            region,
            auth["accessToken"],
            session_id,
            {
                "prompt": build_prompt(row),
                "runtimeSessionId": session_id,
                "evalMode": True,
            },
        )
        text = smoke.event_text(events)
        files = smoke.list_files(runtime_arn, region, auth["accessToken"], session_id)
        terraform_files = [
            file_info.get("key")
            for file_info in files
            if isinstance(file_info, dict) and str(file_info.get("key") or "").endswith((".tf", ".tfvars"))
        ]
        file_contents = {
            key: smoke.read_file(runtime_arn, region, auth["accessToken"], session_id, key)
            for key in terraform_files[:20]
            if key
        }
        contents = "\n\n".join(file_contents.values())
        reference_output = clean(row.get("Reference output") or row.get("Reference Output"))
        combined = f"{text}\n{contents}"
        marker_results = {marker: marker in combined for marker in markers}
        tool_names = smoke.tool_names(events)
        tool_sequence = smoke.tool_call_sequence(events)
        engineer_loop = smoke.engineer_loop_summary(tool_sequence)
        progress = smoke.specialist_events(events)
        missing_markers = [marker for marker, found in marker_results.items() if not found]
        all_agents_called = all(agent in tool_names for agent in AGENT_NAMES)
        passed = bool(text.strip()) and bool(terraform_files) and all_agents_called
        record = {
            "index": index,
            "rowId": row_id(index, row),
            "status": "completed",
            "pass": passed,
            "stack": stack["stack_name"],
            "region": region,
            "sessionId": session_id,
            "userId": auth["userId"],
            "durationSeconds": round(time.time() - started, 2),
            "difficulty": clean(row.get("Difficulty")),
            "resource": clean(row.get("Resource")),
            "prompt": clean(row.get("Prompt")),
            "intent": clean(row.get("Intent")),
            "referenceOutput": reference_output,
            "bleuScore": round(bleu_score(reference_output, contents), 6),
            "eventCount": len(events),
            "toolNames": tool_names,
            "toolCallSequence": tool_sequence,
            "engineerLoop": engineer_loop,
            "allAgentsCalled": all_agents_called,
            "specialistProgress": smoke.specialist_progress_summary(progress),
            "terraformFiles": terraform_files,
            "requiredMarkers": marker_results,
            "missingMarkers": missing_markers,
            "allRequiredMarkersFound": all(marker_results.values()),
            "responsePreview": text[:1200],
        }
        source = write_generated_source(
            source_dir,
            index,
            session_id,
            terraform_files,
            file_contents,
            {
                "index": index,
                "rowId": record["rowId"],
                "sessionId": session_id,
                "difficulty": record["difficulty"],
                "resource": record["resource"],
                "prompt": record["prompt"],
                "intent": record["intent"],
                "referenceOutput": reference_output,
                "bleuScore": record["bleuScore"],
                "toolNames": tool_names,
                "requiredMarkers": marker_results,
                "missingMarkers": missing_markers,
                "pass": passed,
            },
        )
        record["generatedSourceDir"] = source["sourceDir"]
        record["generatedSourceFiles"] = source["sourceFiles"]
        source_path = Path(source["sourceDir"])
        artifact_quality = artifact_quality_check(source_path, file_contents)
        official = run_official_iac_eval(
            source_path,
            rego_policy_for_row(row),
            official_eval,
            terraform_bin,
            opa_bin,
            official_timeout,
            terraform_plugin_cache_dir,
        )
        record["artifactQuality"] = artifact_quality
        record["officialEvaluation"] = official
        if official_eval:
            record["pass"] = bool(record["pass"] and official.get("officialPass"))
        else:
            record["pass"] = bool(record["pass"] and all(marker_results.values()))
        failure = failure_summary(record)
        record["failure_category"] = failure["failureCategory"]
        record["failure_reason"] = failure["failureReason"]
        return record
    except Exception as exc:
        record = {
            "index": index,
            "rowId": row_id(index, row),
            "status": "error",
            "pass": False,
            "stack": stack["stack_name"],
            "region": region,
            "sessionId": session_id,
            "userId": auth["userId"],
            "durationSeconds": round(time.time() - started, 2),
            "difficulty": clean(row.get("Difficulty")),
            "resource": clean(row.get("Resource")),
            "prompt": clean(row.get("Prompt")),
            "intent": clean(row.get("Intent")),
            "error": str(exc),
        }
        failure = failure_summary(record)
        record["failure_category"] = failure["failureCategory"]
        record["failure_reason"] = failure["failureReason"]
        return record


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack-name", default=None)
    parser.add_argument("--dataset-file", default="")
    parser.add_argument("--dataset-url", default=DEFAULT_DATASET_URL)
    parser.add_argument("--output-dir", default="eval-results/iac-eval-chat")
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--limit", type=int, default=3)
    parser.add_argument("--indices-file", default="", help="Optional newline/comma separated dataset indices to run.")
    parser.add_argument("--full", action="store_true", help="Run all remaining rows.")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--confirm-cost", action="store_true", help="Required for --full.")
    parser.add_argument("--official-eval", action="store_true", help="Run upstream-style Terraform plan plus OPA/Rego evaluation using the dataset Rego intent column.")
    parser.add_argument("--terraform-bin", default="terraform")
    parser.add_argument("--opa-bin", default="opa")
    parser.add_argument("--official-timeout", type=int, default=120)
    parser.add_argument("--terraform-plugin-cache-dir", default=str(DEFAULT_TERRAFORM_PLUGIN_CACHE_DIR))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.full and not args.confirm_cost:
        raise SystemExit("--full requires --confirm-cost because this can run for many hours and incur model/runtime cost")

    rows = load_dataset_rows(args.dataset_file or None, args.dataset_url)
    selected = list(enumerate(rows))
    indices = load_indices(args.indices_file)
    if indices:
        selected = [(index, row) for index, row in selected if index in indices]
    if args.start:
        selected = [(index, row) for index, row in selected if index >= args.start]
    if not args.full:
        selected = selected[: args.limit]

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = output_dir / "iac_eval_chat_results.jsonl"
    csv_path = output_dir / "iac_eval_chat_results.csv"
    source_dir = output_dir / "generated-source"
    done = completed_indices(jsonl_path) if args.resume else set()

    stack = smoke.get_stack_config(args.stack_name)
    outputs = stack["outputs"]
    region = stack["region"]
    user_pool_id = smoke.output_key(outputs, "UserPoolId", "CognitoUserPoolId")
    client_id = smoke.output_key(outputs, "UserPoolClientId", "CognitoClientId")
    runtime_arn = smoke.output_key(outputs, "RuntimeArn", "AgentRuntimeArn")
    auth = smoke.create_temp_user(user_pool_id, client_id, region)
    summary = {"totalSelected": len(selected), "completed": 0, "passed": 0, "failed": 0, "skipped": 0}

    try:
        for index, row in selected:
            if index in done:
                summary["skipped"] += 1
                continue
            print(f"Running IaC-Eval row {index}: difficulty={clean(row.get('Difficulty'))} resource={clean(row.get('Resource'))[:120]}", flush=True)
            record = run_one(
                row,
                index,
                stack,
                auth,
                runtime_arn,
                source_dir,
                args.official_eval,
                args.terraform_bin,
                args.opa_bin,
                args.official_timeout,
                args.terraform_plugin_cache_dir,
            )
            write_jsonl(jsonl_path, record)
            rewrite_csv(csv_path, jsonl_path)
            summary["completed"] += 1
            if record.get("pass"):
                summary["passed"] += 1
            else:
                summary["failed"] += 1
            print(
                json.dumps(
                    {
                        "index": index,
                        "status": record.get("status"),
                        "pass": record.get("pass"),
                        "failure": failure_summary(record),
                        "durationSeconds": record.get("durationSeconds"),
                        "allAgentsCalled": record.get("allAgentsCalled"),
                        "engineerLoop": record.get("engineerLoop"),
                        "allRequiredMarkersFound": record.get("allRequiredMarkersFound"),
                        "missingMarkers": record.get("missingMarkers"),
                        "artifactQuality": record.get("artifactQuality"),
                        "officialEvaluation": record.get("officialEvaluation"),
                    },
                    indent=2,
                ),
                flush=True,
            )
    finally:
        smoke.delete_temp_user(user_pool_id, region, auth["username"])

    summary["jsonl"] = str(jsonl_path)
    summary["csv"] = str(csv_path)
    print(json.dumps(summary, indent=2))
    return 0 if summary["failed"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
