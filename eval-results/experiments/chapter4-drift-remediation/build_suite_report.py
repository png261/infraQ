#!/usr/bin/env python3
"""Build a suite-level evidence report for the 20 drift/policy/agent-fix cases."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


CASE_DIR = Path(__file__).resolve().parent
RESULTS = CASE_DIR / "results"
SUITE_PATH = CASE_DIR / "testcases.json"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_suite() -> dict[str, Any]:
    return read_json(SUITE_PATH)


def candidate_result_files(results_dir: Path) -> list[Path]:
    if not results_dir.exists():
        return []
    return sorted(
        path
        for path in results_dir.glob("*.json")
        if path.is_file() and not path.name.endswith("-evidence.json")
    )


def load_results(results_dir: Path) -> dict[str, list[dict[str, Any]]]:
    by_case: dict[str, list[dict[str, Any]]] = {}
    for path in candidate_result_files(results_dir):
        try:
            payload = read_json(path)
        except Exception:
            continue
        case_id = str(payload.get("testcaseId") or "")
        if not case_id:
            continue
        payload["_path"] = str(path)
        by_case.setdefault(case_id, []).append(payload)
    return by_case


def latest_result(results: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not results:
        return None
    return sorted(results, key=lambda item: str(item.get("testId") or item.get("_path") or ""))[-1]


def count_value(section: dict[str, Any] | None, key: str) -> int | None:
    if not isinstance(section, dict):
        return None
    value = section.get(key)
    return value if isinstance(value, int) else None


def policy_ids(section: dict[str, Any] | None) -> set[str]:
    ids: set[str] = set()
    if not isinstance(section, dict):
        return ids
    for item in section.get("policyDetails") or []:
        if isinstance(item, dict) and item.get("policy_id"):
            ids.add(str(item["policy_id"]))
    return ids


def evidence_report_path(result: dict[str, Any]) -> Path:
    path = Path(str(result.get("_path") or ""))
    return path.with_name(path.stem + "-evidence-report.md")


def evidence_has_agent_response(path: Path) -> bool:
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8", errors="replace")
    if "No matching persisted chat session was found" in text:
        return False
    if "Chat session collection failed" in text:
        return False
    return "Agent fixed response:" in text


def evaluate_case(case: dict[str, Any], result: dict[str, Any] | None) -> dict[str, Any]:
    if result is None:
        return {
            "status": "MISSING_EVIDENCE",
            "reason": "No result JSON was found for this testcase.",
        }
    baseline = result.get("baseline")
    drifted = result.get("drifted")
    fixed = result.get("fixed")
    drift_expectation = case.get("driftExpectation") or {}
    fixed_expectation = case.get("fixedExpectation") or {}
    failures: list[str] = []

    baseline_drift = count_value(baseline, "driftAlerts")
    baseline_policy = count_value(baseline, "policyAlerts")
    if baseline_drift != case.get("baselineExpectation", {}).get("driftAlerts"):
        failures.append(f"baseline drift count expected {case.get('baselineExpectation', {}).get('driftAlerts')} got {baseline_drift}")
    if baseline_policy != case.get("baselineExpectation", {}).get("policyAlerts"):
        failures.append(f"baseline policy count expected {case.get('baselineExpectation', {}).get('policyAlerts')} got {baseline_policy}")

    drift_count = count_value(drifted, "driftAlerts")
    policy_count = count_value(drifted, "policyAlerts")
    if drift_count is None or drift_count < int(drift_expectation.get("minDriftAlerts", 0)):
        failures.append(f"drifted drift count expected >= {drift_expectation.get('minDriftAlerts', 0)} got {drift_count}")
    if policy_count is None or policy_count < int(drift_expectation.get("minPolicyAlerts", 0)):
        failures.append(f"drifted policy count expected >= {drift_expectation.get('minPolicyAlerts', 0)} got {policy_count}")
    expected_policy_ids = {str(item) for item in drift_expectation.get("policyIds") or []}
    actual_policy_ids = policy_ids(drifted)
    missing_policy_ids = sorted(expected_policy_ids - actual_policy_ids)
    if missing_policy_ids:
        failures.append(f"missing policy IDs: {', '.join(missing_policy_ids)}")

    fixed_drift = count_value(fixed, "driftAlerts")
    fixed_policy = count_value(fixed, "policyAlerts")
    if fixed_drift != fixed_expectation.get("driftAlerts"):
        failures.append(f"fixed drift count expected {fixed_expectation.get('driftAlerts')} got {fixed_drift}")
    if fixed_policy != fixed_expectation.get("policyAlerts"):
        failures.append(f"fixed policy count expected {fixed_expectation.get('policyAlerts')} got {fixed_policy}")

    report_path = evidence_report_path(result)
    has_agent_response = evidence_has_agent_response(report_path)
    if not has_agent_response:
        failures.append("agent fix response evidence is missing")

    return {
        "status": "PASS" if not failures else "INCOMPLETE",
        "reason": "; ".join(failures) if failures else "All scan counts and agent evidence match expectations.",
        "resultPath": result.get("_path"),
        "evidenceReport": str(report_path) if report_path.exists() else "",
        "hasAgentResponse": has_agent_response,
        "baseline": {
            "driftAlerts": baseline_drift,
            "policyAlerts": baseline_policy,
        },
        "drifted": {
            "driftAlerts": drift_count,
            "policyAlerts": policy_count,
            "policyIds": sorted(actual_policy_ids),
        },
        "fixed": {
            "driftAlerts": fixed_drift,
            "policyAlerts": fixed_policy,
        },
    }


def render_markdown(suite: dict[str, Any], evaluations: list[dict[str, Any]]) -> str:
    passed = sum(1 for item in evaluations if item["evaluation"]["status"] == "PASS")
    incomplete = sum(1 for item in evaluations if item["evaluation"]["status"] == "INCOMPLETE")
    missing = sum(1 for item in evaluations if item["evaluation"]["status"] == "MISSING_EVIDENCE")
    lines = [
        "# Chapter 4 Suite Evidence Report",
        "",
        f"- Suite ID: `{suite.get('suiteId', '-')}`",
        f"- Deployed website: `{suite.get('deployedWebsite', '-')}`",
        f"- Region: `{suite.get('region', '-')}`",
        f"- Total testcases: `{len(evaluations)}`",
        f"- Complete: `{passed}`",
        f"- Incomplete: `{incomplete}`",
        f"- Missing evidence: `{missing}`",
        "",
        "## Case Status",
        "",
        "| ID | Focus | Status | Evidence | Reason |",
        "| --- | --- | --- | --- | --- |",
    ]
    for item in evaluations:
        case = item["case"]
        evaluation = item["evaluation"]
        evidence = evaluation.get("evidenceReport") or evaluation.get("resultPath") or "-"
        if evidence and evidence != "-":
            evidence = f"`{evidence}`"
        reason = str(evaluation.get("reason") or "-").replace("|", "\\|")
        lines.append(
            f"| `{case.get('id')}` | {case.get('title')} | `{evaluation.get('status')}` | {evidence} | {reason} |"
        )
    lines.extend(
        [
            "",
            "## Blocking Evidence",
            "",
        ]
    )
    blocker_files = sorted(RESULTS.glob("live-run-blocker-*.md"))
    if blocker_files:
        for path in blocker_files:
            lines.append(f"- `{path}`")
    else:
        lines.append("- No live-run blocker artifacts recorded.")
    lines.extend(
        [
            "",
            "## Interpretation for Thesis Experiment",
            "",
            "A testcase is marked `PASS` only when the run evidence proves baseline, drifted, and fixed scan expectations and the evidence report contains a matching AI-agent fix response. Cases marked `INCOMPLETE` may still have valid drift/policy scan evidence but are missing the agent response or another required expectation. Cases marked `MISSING_EVIDENCE` still need to be executed against the deployed website.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default=str(RESULTS))
    parser.add_argument("--output", default=str(RESULTS / "suite-evidence-report.md"))
    parser.add_argument("--json-output", default=str(RESULTS / "suite-evidence-report.json"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    suite = load_suite()
    by_case = load_results(Path(args.results_dir))
    evaluations = []
    for case in suite.get("testcases") or []:
        if not isinstance(case, dict):
            continue
        result = latest_result(by_case.get(str(case.get("id") or ""), []))
        evaluations.append({"case": case, "evaluation": evaluate_case(case, result)})

    output = Path(args.output)
    output.write_text(render_markdown(suite, evaluations), encoding="utf-8")
    json_output = Path(args.json_output)
    json_output.write_text(json.dumps({"suite": suite, "evaluations": evaluations}, indent=2, default=str), encoding="utf-8")
    print(json.dumps({"reportPath": str(output), "jsonPath": str(json_output), "cases": len(evaluations)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
