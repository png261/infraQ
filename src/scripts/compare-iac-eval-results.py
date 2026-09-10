#!/usr/bin/env python3
"""Compare multi-agent and LLM-only IaC-Eval JSONL results by row index."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


def load_latest_by_index(path: Path) -> dict[int, dict[str, Any]]:
    rows: dict[int, dict[str, Any]] = {}
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            record = json.loads(line)
            index = record.get("index")
            if isinstance(index, int):
                rows[index] = record
    return rows


def official_pass(record: dict[str, Any]) -> bool:
    return bool((record.get("officialEvaluation") or {}).get("officialPass"))


def official_category(record: dict[str, Any]) -> str:
    return str(record.get("failure_category") or record.get("failureCategory") or "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--multi-agent", default="eval-results/iac-eval-local-core-full/iac_eval_local_results.jsonl")
    parser.add_argument("--llm", default="eval-results/iac-eval-llm-gpt55-match-local/iac_eval_llm_results.jsonl")
    parser.add_argument("--output", default="eval-results/iac-eval-comparison-gpt55.csv")
    args = parser.parse_args()

    multi = load_latest_by_index(Path(args.multi_agent))
    llm = load_latest_by_index(Path(args.llm))
    overlap = sorted(set(multi) & set(llm))
    rows: list[dict[str, Any]] = []
    for index in overlap:
        multi_record = multi[index]
        llm_record = llm[index]
        rows.append(
            {
                "index": index,
                "resource": multi_record.get("resource") or llm_record.get("resource"),
                "difficulty": multi_record.get("difficulty") or llm_record.get("difficulty"),
                "multi_agent_pass": official_pass(multi_record),
                "llm_pass": official_pass(llm_record),
                "multi_agent_failure": official_category(multi_record),
                "llm_failure": official_category(llm_record),
                "multi_agent_bleu": multi_record.get("bleuScore", ""),
                "llm_bleu": llm_record.get("bleuScore", ""),
                "multi_agent_source": multi_record.get("generatedSourceDir", ""),
                "llm_source": llm_record.get("generatedSourceDir", ""),
            }
        )

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "index",
        "resource",
        "difficulty",
        "multi_agent_pass",
        "llm_pass",
        "multi_agent_failure",
        "llm_failure",
        "multi_agent_bleu",
        "llm_bleu",
        "multi_agent_source",
        "llm_source",
    ]
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    summary = {
        "multiAgentRows": len(multi),
        "llmRows": len(llm),
        "overlapRows": len(overlap),
        "multiAgentPassOnOverlap": sum(1 for index in overlap if official_pass(multi[index])),
        "llmPassOnOverlap": sum(1 for index in overlap if official_pass(llm[index])),
        "multiOnlyPass": sum(1 for index in overlap if official_pass(multi[index]) and not official_pass(llm[index])),
        "llmOnlyPass": sum(1 for index in overlap if official_pass(llm[index]) and not official_pass(multi[index])),
        "bothPass": sum(1 for index in overlap if official_pass(multi[index]) and official_pass(llm[index])),
        "bothFail": sum(1 for index in overlap if not official_pass(multi[index]) and not official_pass(llm[index])),
        "output": str(output),
    }
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
