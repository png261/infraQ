#!/usr/bin/env python3
"""Collect scan logs and agent-fix evidence into a thesis-ready report."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import boto3
from boto3.dynamodb.conditions import Key

from run_demo import REGION, api, authenticate_user, output_key, resources_table_name, stack_outputs


CASE_DIR = Path(__file__).resolve().parent
RESULTS = CASE_DIR / "results"
ERROR_PATTERN = re.compile(r"\b(error|failed|failure|exception|traceback|denied|timeout)\b", re.IGNORECASE)
BENIGN_LOG_PATTERNS = (
    re.compile(r"report auto-discover timeout", re.IGNORECASE),
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def is_error_log_line(message: str) -> bool:
    if any(pattern.search(message) for pattern in BENIGN_LOG_PATTERNS):
        return False
    return bool(ERROR_PATTERN.search(message))


def phase_scan_ids(result: dict[str, Any]) -> list[tuple[str, str]]:
    phases = []
    for name in ("baseline", "drifted", "fixed"):
        scan = result.get(name)
        if isinstance(scan, dict) and scan.get("scanId"):
            phases.append((name, str(scan["scanId"])))
    return phases


def collect_logs(api_url: str, id_token: str, scan_id: str) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    next_token = None
    previous_token = None
    log_group = None
    log_stream = None
    for _ in range(10):
        suffix = f"?{urlencode({'nextToken': next_token})}" if next_token else ""
        try:
            payload = api(api_url, id_token, f"/resources/scans/{scan_id}/logs{suffix}")
        except Exception as exc:
            return {
                "scanId": scan_id,
                "logGroupName": log_group,
                "logStreamName": log_stream,
                "eventCount": len(events),
                "errorLines": [f"Log collection failed: {exc}"],
                "tail": [str(event.get("message") or "").rstrip() for event in events][-30:],
                "collectionError": str(exc),
            }
        logs = payload.get("logs") or {}
        log_group = logs.get("logGroupName") or log_group
        log_stream = logs.get("logStreamName") or log_stream
        events.extend(logs.get("events") or [])
        previous_token, next_token = next_token, logs.get("nextForwardToken")
        if not next_token or next_token == previous_token:
            break
    messages = [str(event.get("message") or "").rstrip() for event in events]
    error_lines = [message for message in messages if is_error_log_line(message)]
    return {
        "scanId": scan_id,
        "logGroupName": log_group,
        "logStreamName": log_stream,
        "eventCount": len(events),
        "errorLines": error_lines[:40],
        "tail": messages[-30:],
    }


def collect_logs_direct(table: Any, user_id: str, scan_id: str) -> dict[str, Any]:
    scan = table.get_item(Key={"pk": user_id, "sk": f"SCAN#{scan_id}"}).get("Item")
    if not scan:
        return {
            "scanId": scan_id,
            "logGroupName": None,
            "logStreamName": None,
            "eventCount": 0,
            "errorLines": ["Scan record not found in DynamoDB."],
            "tail": [],
        }
    build_id = scan.get("codeBuildBuildId")
    if not build_id:
        return {
            "scanId": scan_id,
            "logGroupName": None,
            "logStreamName": None,
            "eventCount": 0,
            "errorLines": ["Scan record has no CodeBuild build ID."],
            "tail": [],
        }
    codebuild = boto3.client("codebuild", region_name=REGION)
    logs_client = boto3.client("logs", region_name=REGION)
    builds = codebuild.batch_get_builds(ids=[build_id]).get("builds", [])
    if not builds:
        return {
            "scanId": scan_id,
            "logGroupName": None,
            "logStreamName": None,
            "eventCount": 0,
            "errorLines": [f"CodeBuild build not found: {build_id}"],
            "tail": [],
        }
    log_info = builds[0].get("logs") or {}
    log_group = log_info.get("groupName")
    log_stream = log_info.get("streamName")
    if not log_group or not log_stream:
        return {
            "scanId": scan_id,
            "logGroupName": log_group,
            "logStreamName": log_stream,
            "eventCount": 0,
            "errorLines": ["CodeBuild build has no CloudWatch log stream."],
            "tail": [],
        }
    events: list[dict[str, Any]] = []
    next_token = None
    previous_token = None
    for _ in range(10):
        params: dict[str, Any] = {
            "logGroupName": log_group,
            "logStreamName": log_stream,
            "startFromHead": True,
            "limit": 200,
        }
        if next_token:
            params["nextToken"] = next_token
        response = logs_client.get_log_events(**params)
        events.extend(response.get("events") or [])
        previous_token, next_token = next_token, response.get("nextForwardToken")
        if not next_token or next_token == previous_token:
            break
    messages = [str(event.get("message") or "").rstrip() for event in events]
    error_lines = [message for message in messages if is_error_log_line(message)]
    return {
        "scanId": scan_id,
        "logGroupName": log_group,
        "logStreamName": log_stream,
        "eventCount": len(events),
        "errorLines": error_lines[:40],
        "tail": messages[-30:],
    }


def message_text(message: dict[str, Any]) -> str:
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks = []
        for item in content:
            if isinstance(item, dict):
                chunks.append(str(item.get("text") or item.get("content") or ""))
            else:
                chunks.append(str(item))
        return "\n".join(chunk for chunk in chunks if chunk)
    return str(content or "")


def session_matches(session: dict[str, Any], result: dict[str, Any]) -> bool:
    haystack = json.dumps(session, default=str)
    backend_id = str((result.get("stateBackend") or {}).get("backendId") or "")
    scan_ids = [scan_id for _, scan_id in phase_scan_ids(result)]
    markers = [backend_id, *scan_ids, str(result.get("testcaseId") or "")]
    return any(marker and marker in haystack for marker in markers)


def collect_agent_sessions(api_url: str, id_token: str, result: dict[str, Any]) -> list[dict[str, Any]]:
    payload = api(api_url, id_token, "/user/chat-sessions")
    sessions = payload.get("sessions") or []
    matches = []
    for session in sessions:
        if not isinstance(session, dict) or not session_matches(session, result):
            continue
        history = [item for item in session.get("history") or [] if isinstance(item, dict)]
        user_prompts = [message_text(item) for item in history if item.get("role") == "user"]
        assistant_responses = [message_text(item) for item in history if item.get("role") == "assistant"]
        matches.append(
            {
                "sessionId": session.get("sessionId") or session.get("id"),
                "name": session.get("name"),
                "startDate": session.get("startDate"),
                "endDate": session.get("endDate"),
                "repository": session.get("repository"),
                "stateBackend": session.get("stateBackend"),
                "pullRequest": session.get("pullRequest"),
                "lastUserPrompt": user_prompts[-1] if user_prompts else "",
                "lastAssistantResponse": assistant_responses[-1] if assistant_responses else "",
            }
        )
    return matches


def collect_agent_sessions_direct(table: Any, user_id: str, result: dict[str, Any]) -> list[dict[str, Any]]:
    response = table.query(
        KeyConditionExpression=Key("pk").eq(user_id) & Key("sk").begins_with("SESSION#"),
        ScanIndexForward=False,
    )
    sessions = response.get("Items") or []
    matches = []
    for session in sessions:
        if not isinstance(session, dict) or not session_matches(session, result):
            continue
        history = [item for item in session.get("history") or [] if isinstance(item, dict)]
        user_prompts = [message_text(item) for item in history if item.get("role") == "user"]
        assistant_responses = [message_text(item) for item in history if item.get("role") == "assistant"]
        matches.append(
            {
                "sessionId": session.get("sessionId") or session.get("id"),
                "name": session.get("name"),
                "startDate": session.get("startDate"),
                "endDate": session.get("endDate"),
                "repository": session.get("repository"),
                "stateBackend": session.get("stateBackend"),
                "pullRequest": session.get("pullRequest"),
                "lastUserPrompt": user_prompts[-1] if user_prompts else "",
                "lastAssistantResponse": assistant_responses[-1] if assistant_responses else "",
            }
        )
    return matches


def collect_pull_requests(api_url: str, id_token: str, result: dict[str, Any]) -> list[dict[str, Any]]:
    repository = ((result.get("stateBackend") or {}).get("repository") or {}).get("fullName")
    if not repository:
        repository = "png261/chapter4-drift-demo"
    payload = api(api_url, id_token, f"/github/pull-requests?{urlencode({'repository': repository, 'state': 'all'})}")
    pulls = payload.get("pullRequests") or []
    markers = [
        str(result.get("testcaseId") or ""),
        *[scan_id for _, scan_id in phase_scan_ids(result)],
        str((result.get("stateBackend") or {}).get("backendId") or ""),
    ]
    matched = []
    for pull in pulls:
        text = json.dumps(pull, default=str)
        if any(marker and marker in text for marker in markers):
            matched.append(pull)
    return matched


def collect_pull_requests_direct(table: Any, result: dict[str, Any]) -> list[dict[str, Any]]:
    repository = ((result.get("stateBackend") or {}).get("repository") or {}).get("fullName")
    if not repository:
        repository = "png261/chapter4-drift-demo"
    response = table.query(
        KeyConditionExpression=Key("pk").eq(f"GITHUB#{repository}") & Key("sk").begins_with("PR#"),
        ScanIndexForward=False,
    )
    pulls = response.get("Items") or []
    markers = [
        str(result.get("testcaseId") or ""),
        *[scan_id for _, scan_id in phase_scan_ids(result)],
        str((result.get("stateBackend") or {}).get("backendId") or ""),
    ]
    matched = []
    for pull in pulls:
        text = json.dumps(pull, default=str)
        if any(marker and marker in text for marker in markers):
            matched.append(pull)
    return matched


def fenced(text: str, limit: int = 3500) -> str:
    value = (text or "").strip()
    if len(value) > limit:
        value = value[:limit].rstrip() + "\n... [truncated]"
    if not value:
        value = "Not collected."
    return f"```text\n{value}\n```"


def render_report(result: dict[str, Any], logs: dict[str, Any], sessions: list[dict[str, Any]], pulls: list[dict[str, Any]]) -> str:
    backend = result.get("stateBackend") or {}
    lines = [
        "# Chapter 4 Evidence Report: Drift, Policy Detection, and AI-Agent Fix",
        "",
        "## Run Metadata",
        "",
        f"- Testcase ID: `{result.get('testcaseId', '-')}`",
        f"- Run ID: `{result.get('testId', '-')}`",
        f"- Web app: `{result.get('webAppUrl', '-')}`",
        f"- State backend: `{backend.get('backendId', '-')}`",
        f"- Terraform state: `s3://{backend.get('bucket', '-')}/{backend.get('key', '-')}`",
        f"- Region: `{backend.get('region', '-')}`",
        "",
        "## Scan Summary",
        "",
        "| Phase | Scan ID | Status | Drift alerts | Policy alerts | Error |",
        "| --- | --- | --- | ---: | ---: | --- |",
    ]
    for phase in ("baseline", "drifted", "fixed"):
        scan = result.get(phase) or {}
        lines.append(
            f"| {phase.title()} | `{scan.get('scanId', '-')}` | `{scan.get('status', '-')}` | "
            f"{scan.get('driftAlerts', '-')} | {scan.get('policyAlerts', '-')} | {scan.get('error') or '-'} |"
        )
    lines.extend(["", "## Detected Errors and Cloudrift Logs", ""])
    for phase, scan_id in phase_scan_ids(result):
        log = logs.get(scan_id) or {}
        lines.extend(
            [
                f"### {phase.title()} Scan",
                "",
                f"- Scan ID: `{scan_id}`",
                f"- Log group: `{log.get('logGroupName') or '-'}`",
                f"- Log stream: `{log.get('logStreamName') or '-'}`",
                f"- Events collected: `{log.get('eventCount', 0)}`",
                "",
                "Error-related log lines:",
                "",
                fenced("\n".join(log.get("errorLines") or []) or "No error-related log lines found."),
                "",
                "Log tail:",
                "",
                fenced("\n".join(log.get("tail") or [])),
                "",
            ]
        )
    lines.extend(["## AI-Agent Fix Evidence", ""])
    if sessions:
        for index, session in enumerate(sessions, start=1):
            pr = session.get("pullRequest") or {}
            lines.extend(
                [
                    f"### Agent Session {index}",
                    "",
                    f"- Session ID: `{session.get('sessionId') or '-'}`",
                    f"- Name: `{session.get('name') or '-'}`",
                    f"- Started: `{session.get('startDate') or '-'}`",
                    f"- Ended: `{session.get('endDate') or '-'}`",
                    f"- Pull request: `{pr.get('url') or pr.get('html_url') or '-'}`",
                    "",
                    "User fix prompt:",
                    "",
                    fenced(session.get("lastUserPrompt") or ""),
                    "",
                    "Agent fixed response:",
                    "",
                    fenced(session.get("lastAssistantResponse") or "", limit=6000),
                    "",
                ]
            )
    else:
        lines.extend(
            [
                "No matching persisted chat session was found for this testcase.",
                "",
                "For the thesis experiment, run the website fix action after the drifted scan and rerun this collector. The report will then include the user fix prompt, the agent's final response, and pull request metadata.",
                "",
            ]
        )
    lines.extend(["## Pull Request Evidence", ""])
    if pulls:
        for pull in pulls:
            lines.extend(
                [
                    f"- `#{pull.get('number', '-')}` {pull.get('title', '-')}: {pull.get('url') or pull.get('htmlUrl') or pull.get('html_url') or '-'}",
                ]
            )
    else:
        lines.append("No matching pull request record was found for this testcase.")
    lines.extend(
        [
            "",
            "## Experiment Interpretation",
            "",
            "This run provides evidence for three experiment claims:",
            "",
            "1. The deployed website can trigger Cloudrift scans against a real S3 Terraform state backend.",
            "2. The scanner can report drift and policy findings with concrete resource context.",
            "3. The selected finding can be handed to the AI-agent remediation workflow, producing a scoped fix response and, when repository write access is configured, a pull request.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", default=str(RESULTS / "ch4-demo-20260520-dev2.json"))
    parser.add_argument("--output", default="")
    parser.add_argument("--username", default=os.environ.get("CH4_COGNITO_USERNAME", ""))
    parser.add_argument("--password", default=os.environ.get("CH4_COGNITO_PASSWORD", ""))
    parser.add_argument("--id-token", default=os.environ.get("CH4_ID_TOKEN", ""))
    parser.add_argument("--api-collection", action="store_true", help="Collect live evidence through the deployed Resources API instead of AWS direct reads.")
    parser.add_argument("--no-live", action="store_true", help="Generate report from result JSON only.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result_path = Path(args.result)
    result = read_json(result_path)
    output = Path(args.output) if args.output else result_path.with_name(result_path.stem + "-evidence-report.md")

    logs: dict[str, Any] = {}
    sessions: list[dict[str, Any]] = []
    pulls: list[dict[str, Any]] = []
    if not args.no_live and not args.api_collection:
        user_id = str((result.get("testUser") or {}).get("userId") or "")
        if not user_id:
            raise SystemExit("result JSON does not include testUser.userId; use --api-collection with credentials instead")
        table = boto3.resource("dynamodb", region_name=REGION).Table(resources_table_name())
        for _, scan_id in phase_scan_ids(result):
            logs[scan_id] = collect_logs_direct(table, user_id, scan_id)
        sessions = collect_agent_sessions_direct(table, user_id, result)
        pulls = collect_pull_requests_direct(table, result)
    elif not args.no_live:
        outputs = stack_outputs()
        api_url = output_key(outputs, "ResourcesApiUrl")
        id_token = args.id_token
        if not id_token:
            username = args.username or str((result.get("testUser") or {}).get("username") or "")
            password = args.password or str((result.get("testUser") or {}).get("password") or "")
            client_id = output_key(outputs, "CognitoClientId", "UserPoolClientId")
            id_token = authenticate_user(client_id, username, password)["idToken"]
        for _, scan_id in phase_scan_ids(result):
            logs[scan_id] = collect_logs(api_url, id_token, scan_id)
        try:
            sessions = collect_agent_sessions(api_url, id_token, result)
        except Exception as exc:
            sessions = [
                {
                    "sessionId": "collection-error",
                    "name": "Chat session collection failed",
                    "lastUserPrompt": "",
                    "lastAssistantResponse": str(exc),
                }
            ]
        try:
            pulls = collect_pull_requests(api_url, id_token, result)
        except Exception as exc:
            pulls = [{"number": "-", "title": f"Pull request collection failed: {exc}", "url": "-"}]

    output.write_text(render_report(result, logs, sessions, pulls), encoding="utf-8")
    print(json.dumps({"reportPath": str(output), "sessions": len(sessions), "pullRequests": len(pulls)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
