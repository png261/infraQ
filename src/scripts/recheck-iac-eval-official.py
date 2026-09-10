#!/usr/bin/env python3
"""Run official IaC-Eval Terraform plan + OPA checks on saved source folders."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
EVAL_PATH = ROOT / "eval-iac-eval-chat.py"
DEFAULT_DATASET_URL = "https://huggingface.co/datasets/autoiac-project/iac-eval/resolve/main/data.csv"


def load_eval_module():
    spec = importlib.util.spec_from_file_location("iac_eval_chat", EVAL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {EVAL_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


eval_chat = load_eval_module()


def source_index(path: Path) -> int | None:
    match = re.match(r"row-(\d{4})-", path.name)
    if not match:
        return None
    return int(match.group(1))


def tf_contents(source_dir: Path) -> dict[str, str]:
    return {
        str(path.relative_to(source_dir)): path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(source_dir.rglob("*.tf"))
    }


def flatten_record(record: dict[str, Any]) -> dict[str, Any]:
    official = record["officialEvaluation"]
    quality = record["artifactQuality"]
    failure = eval_chat.failure_summary(
        {
            "pass": official["officialPass"],
            "status": "completed",
            "allAgentsCalled": True,
            "allRequiredMarkersFound": True,
            "artifactQuality": quality,
            "officialEvaluation": official,
        }
    )
    return {
        "index": record["index"],
        "source_dir": record["sourceDir"],
        "terraform_files": ", ".join(record["terraformFiles"]),
        "bleu_score": record.get("bleuScore", ""),
        "failure_category": failure["failureCategory"],
        "failure_reason": failure["failureReason"],
        "artifact_complete_pass": quality["artifactCompletePass"],
        "artifact_missing_files": ", ".join(quality["missingPathModuleFiles"]),
        "quality_gate_pass": quality["qualityGatePass"],
        "quality_findings_json": json.dumps(quality["qualityFindings"], ensure_ascii=False, sort_keys=True),
        "official_plan_success": official["terraformPlanSuccess"],
        "official_opa_result": official["opaEvaluationResult"],
        "official_pass": official["officialPass"],
        "default_input_files": ", ".join(official.get("defaultInputFiles") or []),
        "created_missing_files": ", ".join(official.get("createdMissingFiles") or []),
        "official_error": official["terraformPlanError"] or official["opaEvaluationError"] or official["notes"],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-file", default="")
    parser.add_argument("--dataset-url", default=DEFAULT_DATASET_URL)
    parser.add_argument("--source-root", default="eval-results/iac-eval-chat-10-final/generated-source")
    parser.add_argument("--output-dir", default="eval-results/iac-eval-chat-10-final/official-recheck")
    parser.add_argument("--terraform-bin", default="terraform")
    parser.add_argument("--opa-bin", default="opa")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--terraform-plugin-cache-dir", default=str(eval_chat.DEFAULT_TERRAFORM_PLUGIN_CACHE_DIR))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = eval_chat.load_dataset_rows(args.dataset_file or None, args.dataset_url)
    source_root = Path(args.source_root)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, Any]] = []
    for source_dir in sorted(path for path in source_root.iterdir() if path.is_dir() and path.name.startswith("row-")):
        index = source_index(source_dir)
        if index is None or index >= len(rows):
            continue
        contents = tf_contents(source_dir)
        generated_code = "\n\n".join(contents.values())
        quality = eval_chat.artifact_quality_check(source_dir, contents)
        official = eval_chat.run_official_iac_eval(
            source_dir,
            eval_chat.rego_policy_for_row(rows[index]),
            True,
            args.terraform_bin,
            args.opa_bin,
            args.timeout,
            args.terraform_plugin_cache_dir,
        )
        record = {
            "index": index,
            "sourceDir": str(source_dir),
            "terraformFiles": sorted(contents),
            "bleuScore": round(eval_chat.bleu_score(eval_chat.clean(rows[index].get("Reference output") or rows[index].get("Reference Output")), generated_code), 6),
            "artifactQuality": quality,
            "officialEvaluation": official,
        }
        records.append(record)
        print(json.dumps(flatten_record(record), ensure_ascii=False), flush=True)

    json_path = output_dir / "official_recheck_results.json"
    csv_path = output_dir / "official_recheck_results.csv"
    json_path.write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8")
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        fieldnames = list(flatten_record(records[0]).keys()) if records else []
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(flatten_record(record) for record in records)

    summary = {
        "rows": len(records),
        "officialPassed": sum(1 for record in records if record["officialEvaluation"].get("officialPass")),
        "planPassed": sum(1 for record in records if record["officialEvaluation"].get("terraformPlanSuccess")),
        "opaPassed": sum(1 for record in records if record["officialEvaluation"].get("opaEvaluationResult") == "Success"),
        "artifactCompletePassed": sum(1 for record in records if record["artifactQuality"].get("artifactCompletePass")),
        "qualityGatePassed": sum(1 for record in records if record["artifactQuality"].get("qualityGatePass")),
        "avgBleuScore": sum(float(record.get("bleuScore") or 0) for record in records) / len(records) if records else 0,
        "json": str(json_path),
        "csv": str(csv_path),
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)
    return 0 if summary["officialPassed"] == summary["rows"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
