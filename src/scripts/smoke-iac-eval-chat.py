#!/usr/bin/env python3
"""Run a one-row IaC-Eval smoke test against the deployed chat runtime."""

from __future__ import annotations

import argparse
import base64
import json
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any

import boto3
from botocore.exceptions import ClientError

from utils import get_stack_config


IAC_EVAL_PROMPT = """Use this as an IaC-Eval benchmark task for AWS Terraform/OpenTofu generation.

Benchmark row:
- Resource: aws_cloudwatch_log_group, aws_cloudwatch_log_resource_policy, aws_route53_query_log, aws_route53_zone, aws_iam_policy_document
- Difficulty: 5
- Prompt: Configure a query log that can create a log stream and put log events using Route 53 resources. Name the zone "primary", the cloudwatch log group "aws_route53_example_com", and the cloudwatch log resource policy "route53-query-logging-policy".
- Intent: Has one aws_route53_zone resource with name. Has one aws_cloudwatch_log_group. Has one aws_cloudwatch_log_resource_policy with policy_document enabling logs:CreateLogStream and logs:PutLogEvents and with policy_name. Has one aws_route53_query_log with cloudwatch_log_group_arn referencing the log group, zone_id referencing the zone, and depends_on referencing the resource policy.

Rules:
- Do not ask me for more information unless the benchmark row is impossible or unsafe.
- Do not use any reference answer.
- Create a minimal deployable Terraform/OpenTofu solution for AWS only.
- Use provider "aws" and region "us-east-1".
- Do not apply infrastructure.

Multi-agent workflow I want to test:
1. Architect: identify the required AWS resources, dependencies, and resource graph.
2. Engineer: write the Terraform/OpenTofu files.
3. Reviewer: check correctness against the benchmark prompt and likely Rego intent.
4. Security: check IAM, public exposure, encryption, and unsafe defaults.
5. Cost/capacity: identify any cost or quota risks.
6. DevOps: run or propose validation commands such as terraform fmt, terraform validate, policy scan, and plan-safe checks.
7. Limit Engineer to at most 3 total implementation/fix passes for this benchmark row.

Return changed files, validation commands/results, agent findings, and final Terraform summary."""

REQUIRED_MARKERS = [
    "aws_route53_zone",
    "primary",
    "aws_cloudwatch_log_group",
    "aws_route53_example_com",
    "aws_cloudwatch_log_resource_policy",
    "route53-query-logging-policy",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "aws_route53_query_log",
]


def fail(message: str) -> None:
    raise RuntimeError(message)


def output_key(outputs: dict[str, str], *names: str) -> str:
    for name in names:
        value = outputs.get(name)
        if value:
            return value
    fail(f"Missing CloudFormation output. Tried: {', '.join(names)}")


def decode_jwt_claims(token: str) -> dict[str, Any]:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload.encode("utf-8")))


def random_password() -> str:
    return f"Sm0ke!{secrets.token_urlsafe(18)}aA1!"


def create_temp_user(user_pool_id: str, client_id: str, region: str) -> dict[str, str]:
    cognito = boto3.client("cognito-idp", region_name=region)
    username = f"iac-eval-smoke-{uuid.uuid4().hex[:12]}@example.com"
    password = random_password()
    cognito.admin_create_user(
        UserPoolId=user_pool_id,
        Username=username,
        UserAttributes=[
            {"Name": "email", "Value": username},
            {"Name": "email_verified", "Value": "true"},
        ],
        MessageAction="SUPPRESS",
    )
    cognito.admin_set_user_password(
        UserPoolId=user_pool_id,
        Username=username,
        Password=password,
        Permanent=True,
    )
    auth = cognito.initiate_auth(
        AuthFlow="USER_PASSWORD_AUTH",
        ClientId=client_id,
        AuthParameters={"USERNAME": username, "PASSWORD": password},
    )
    tokens = auth["AuthenticationResult"]
    claims = decode_jwt_claims(tokens["IdToken"])
    return {
        "username": username,
        "accessToken": tokens["AccessToken"],
        "idToken": tokens["IdToken"],
        "userId": claims["sub"],
    }


def delete_temp_user(user_pool_id: str, region: str, username: str) -> None:
    try:
        boto3.client("cognito-idp", region_name=region).admin_delete_user(
            UserPoolId=user_pool_id,
            Username=username,
        )
    except ClientError:
        pass


def runtime_url(runtime_arn: str, region: str) -> str:
    escaped = urllib.parse.quote(runtime_arn, safe="")
    return f"https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{escaped}/invocations?qualifier=DEFAULT"


def invoke_runtime(runtime_arn: str, region: str, access_token: str, session_id: str, payload: dict[str, Any]) -> list[dict[str, Any]]:
    transient_statuses = {429, 500, 502, 503, 504}
    for attempt in range(1, 6):
        request = urllib.request.Request(
            runtime_url(runtime_arn, region),
            data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
                "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id": session_id,
                "X-Amzn-Trace-Id": f"1-{int(time.time()):08x}-{uuid.uuid4().hex[:24]}",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                text = response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            if exc.code not in transient_statuses or attempt == 5:
                raise RuntimeError(body) from exc
            time.sleep(min(90, 5 * attempt * attempt))
            continue
        except urllib.error.URLError as exc:
            if attempt == 5:
                raise RuntimeError(str(exc)) from exc
            time.sleep(min(90, 5 * attempt * attempt))
            continue

        events = []
        for line in text.splitlines():
            if not line.startswith("data:"):
                continue
            raw = line.split("data:", 1)[1].strip()
            if raw:
                events.append(json.loads(raw))
        transient_event_error = ""
        for event in events:
            if event.get("status") != "error":
                continue
            transient_event_error = str(event.get("error") or "AgentCore returned an error")
            if "SERVICE_UNAVAILABLE" not in transient_event_error and "temporarily unavailable" not in transient_event_error:
                raise RuntimeError(transient_event_error)
        if transient_event_error:
            if attempt == 5:
                raise RuntimeError(transient_event_error)
            time.sleep(min(90, 5 * attempt * attempt))
            continue
        return events

    raise RuntimeError("AgentCore invocation failed after retries")


def event_text(events: list[dict[str, Any]]) -> str:
    chunks: list[str] = []
    for event in events:
        if event.get("data"):
            chunks.append(str(event["data"]))
        message = event.get("message")
        if isinstance(message, dict):
            content = message.get("content")
            if isinstance(content, list):
                chunks.extend(str(item.get("text") or "") for item in content if isinstance(item, dict))
            elif isinstance(content, str):
                chunks.append(content)
    return "".join(chunks)


def specialist_events(events: list[dict[str, Any]]) -> list[dict[str, str]]:
    found: list[dict[str, str]] = []
    for event in events:
        progress = event.get("specialistToolProgress")
        if isinstance(progress, dict):
            found.append(
                {
                    "phase": str(progress.get("phase") or ""),
                    "message": str(progress.get("message") or ""),
                }
            )
        stream_event = event.get("tool_stream_event")
        if isinstance(stream_event, dict):
            data = stream_event.get("data")
            progress = data.get("specialistToolProgress") if isinstance(data, dict) else None
            if isinstance(progress, dict):
                found.append(
                    {
                        "phase": str(progress.get("phase") or ""),
                        "message": str(progress.get("message") or ""),
                    }
                )
    return found


def specialist_progress_summary(progress: list[dict[str, str]]) -> dict[str, Any]:
    counts: dict[str, int] = {}
    completed: list[str] = []
    started: list[str] = []
    for item in progress:
        message = item.get("message", "")
        for agent_name in [
            "architect_agent",
            "engineer_agent",
            "reviewer_agent",
            "security_prover_agent",
            "cost_capacity_agent",
            "devops_agent",
        ]:
            if agent_name not in message:
                continue
            counts[agent_name] = counts.get(agent_name, 0) + 1
            if item.get("phase") == "started" and agent_name not in started:
                started.append(agent_name)
            if item.get("phase") == "completed" and agent_name not in completed:
                completed.append(agent_name)
    return {
        "eventCountsByAgent": counts,
        "startedAgents": started,
        "completedAgents": completed,
    }


def tool_names(events: list[dict[str, Any]]) -> list[str]:
    names: list[str] = []

    def add_name(value: Any) -> None:
        if isinstance(value, str) and value and value not in names:
            names.append(value)

    for event in events:
        current = event.get("current_tool_use")
        if isinstance(current, dict):
            add_name(current.get("name"))
        stream_event = event.get("tool_stream_event")
        if isinstance(stream_event, dict):
            tool_use = stream_event.get("tool_use")
            if isinstance(tool_use, dict):
                add_name(tool_use.get("name"))
        message = event.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        if isinstance(content, list):
            for block in content:
                tool_use = block.get("toolUse") if isinstance(block, dict) else None
                if isinstance(tool_use, dict):
                    add_name(tool_use.get("name"))
    return names


def tool_call_sequence(events: list[dict[str, Any]]) -> list[str]:
    sequence: list[str] = []

    def add_name(value: Any) -> None:
        if not isinstance(value, str) or not value:
            return
        if sequence and sequence[-1] == value:
            return
        sequence.append(value)

    for event in events:
        current = event.get("current_tool_use")
        if isinstance(current, dict):
            add_name(current.get("name"))
        stream_event = event.get("tool_stream_event")
        if isinstance(stream_event, dict):
            tool_use = stream_event.get("tool_use")
            if isinstance(tool_use, dict):
                add_name(tool_use.get("name"))
        message = event.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        if isinstance(content, list):
            for block in content:
                tool_use = block.get("toolUse") if isinstance(block, dict) else None
                if isinstance(tool_use, dict):
                    add_name(tool_use.get("name"))
    return sequence


def engineer_loop_summary(sequence: list[str]) -> dict[str, Any]:
    verifier_agents = {
        "reviewer_agent",
        "security_prover_agent",
        "cost_capacity_agent",
        "devops_agent",
    }
    engineer_positions = [index for index, name in enumerate(sequence) if name == "engineer_agent"]
    verifier_positions = [index for index, name in enumerate(sequence) if name in verifier_agents]
    return {
        "engineerCallCount": len(engineer_positions),
        "verificationCallCount": len(verifier_positions),
        "engineerAfterVerifier": any(
            engineer_index > verifier_index
            for engineer_index in engineer_positions
            for verifier_index in verifier_positions
        ),
        "engineerAfterReviewer": any(
            engineer_index > reviewer_index
            for engineer_index in engineer_positions
            for reviewer_index, name in enumerate(sequence)
            if name == "reviewer_agent"
        ),
    }


def list_files(runtime_arn: str, region: str, access_token: str, session_id: str) -> list[dict[str, Any]]:
    events = invoke_runtime(
        runtime_arn,
        region,
        access_token,
        session_id,
        {
            "prompt": "list files",
            "runtimeSessionId": session_id,
            "filesystemAction": "listFiles",
        },
    )
    for event in events:
        if event.get("status") == "ok" and isinstance(event.get("files"), list):
            return event["files"]
    return []


def read_file(runtime_arn: str, region: str, access_token: str, session_id: str, key: str) -> str:
    events = invoke_runtime(
        runtime_arn,
        region,
        access_token,
        session_id,
        {
            "prompt": "read file",
            "runtimeSessionId": session_id,
            "filesystemAction": "getFileContent",
            "fileKey": key,
        },
    )
    for event in events:
        file_info = event.get("file")
        if event.get("status") == "ok" and isinstance(file_info, dict):
            return str(file_info.get("content") or "")
    return ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack-name", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    stack = get_stack_config(args.stack_name)
    outputs = stack["outputs"]
    region = stack["region"]
    user_pool_id = output_key(outputs, "UserPoolId", "CognitoUserPoolId")
    client_id = output_key(outputs, "UserPoolClientId", "CognitoClientId")
    runtime_arn = output_key(outputs, "RuntimeArn", "AgentRuntimeArn")
    auth = create_temp_user(user_pool_id, client_id, region)
    session_id = str(uuid.uuid4())
    try:
        events = invoke_runtime(
            runtime_arn,
            region,
            auth["accessToken"],
            session_id,
            {
                "prompt": IAC_EVAL_PROMPT,
                "runtimeSessionId": session_id,
            },
        )
        text = event_text(events)
        files = list_files(runtime_arn, region, auth["accessToken"], session_id)
        terraform_files = [
            file_info.get("key")
            for file_info in files
            if isinstance(file_info, dict) and str(file_info.get("key") or "").endswith((".tf", ".tfvars"))
        ]
        contents = "\n\n".join(
            read_file(runtime_arn, region, auth["accessToken"], session_id, key)
            for key in terraform_files[:10]
            if key
        )
        combined = f"{text}\n{contents}"
        marker_results = {marker: marker in combined for marker in REQUIRED_MARKERS}
        progress = specialist_events(events)
        summary = {
            "stack": stack["stack_name"],
            "region": region,
            "sessionId": session_id,
            "userId": auth["userId"],
            "eventCount": len(events),
            "toolNames": tool_names(events),
            "toolCallSequence": tool_call_sequence(events),
            "engineerLoop": engineer_loop_summary(tool_call_sequence(events)),
            "specialistProgress": specialist_progress_summary(progress),
            "terraformFiles": terraform_files,
            "requiredMarkers": marker_results,
            "allRequiredMarkersFound": all(marker_results.values()),
            "responsePreview": text[:1200],
        }
        print(json.dumps(summary, indent=2))
        return 0 if text.strip() and terraform_files and all(marker_results.values()) else 2
    finally:
        delete_temp_user(user_pool_id, region, auth["username"])


if __name__ == "__main__":
    raise SystemExit(main())
