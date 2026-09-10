#!/usr/bin/env python3
"""Validate the Chapter 4 drift/policy/AI-fix testcase suite."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REQUIRED_CASE_KEYS = {
    "id",
    "title",
    "service",
    "fixture",
    "liveMutation",
    "baselineExpectation",
    "driftExpectation",
    "agentFixExpectation",
    "fixedExpectation",
}


def main() -> int:
    payload = json.loads((ROOT / "testcases.json").read_text(encoding="utf-8"))
    cases = payload.get("testcases")
    if not isinstance(cases, list):
        raise SystemExit("testcases must be a list")
    if len(cases) != 20:
        raise SystemExit(f"expected 20 testcases, found {len(cases)}")

    seen: set[str] = set()
    for index, case in enumerate(cases, start=1):
        if not isinstance(case, dict):
            raise SystemExit(f"case {index} must be an object")
        missing = sorted(REQUIRED_CASE_KEYS - set(case))
        if missing:
            raise SystemExit(f"{case.get('id', index)} missing keys: {', '.join(missing)}")
        case_id = str(case["id"])
        if case_id in seen:
            raise SystemExit(f"duplicate testcase id: {case_id}")
        seen.add(case_id)
        drift = case["driftExpectation"]
        fixed = case["fixedExpectation"]
        if not isinstance(drift, dict) or "minDriftAlerts" not in drift or "minPolicyAlerts" not in drift:
            raise SystemExit(f"{case_id} driftExpectation must include minDriftAlerts and minPolicyAlerts")
        if not isinstance(fixed, dict) or fixed.get("driftAlerts") != 0 or fixed.get("policyAlerts") != 0:
            raise SystemExit(f"{case_id} fixedExpectation must require 0 drift and 0 policy alerts")
        if not str(case["agentFixExpectation"]).strip():
            raise SystemExit(f"{case_id} agentFixExpectation must not be empty")

    print(f"validated {len(cases)} testcases for {payload['deployedWebsite']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
