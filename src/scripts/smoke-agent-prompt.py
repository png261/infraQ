#!/usr/bin/env python3
"""Invoke the deployed AgentCore runtime with a single prompt."""

from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any

import boto3

from utils import get_stack_config


def decode_jwt_claims(token: str) -> dict[str, Any]:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload.encode("utf-8")))


def authenticate(client_id: str, region: str, username: str, password: str) -> dict[str, str]:
    cognito = boto3.client("cognito-idp", region_name=region)
    auth = cognito.initiate_auth(
        AuthFlow="USER_PASSWORD_AUTH",
        ClientId=client_id,
        AuthParameters={"USERNAME": username, "PASSWORD": password},
    )
    tokens = auth["AuthenticationResult"]
    return {
        "accessToken": tokens["AccessToken"],
        "idToken": tokens["IdToken"],
        "userId": decode_jwt_claims(tokens["IdToken"])["sub"],
    }


def runtime_url(runtime_arn: str, region: str) -> str:
    escaped = urllib.parse.quote(runtime_arn, safe="")
    return f"https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{escaped}/invocations?qualifier=DEFAULT"


def invoke(runtime_arn: str, region: str, access_token: str, prompt: str) -> list[dict[str, Any]]:
    session_id = str(uuid.uuid4())
    request = urllib.request.Request(
        runtime_url(runtime_arn, region),
        data=json.dumps(
            {
                "prompt": prompt,
                "runtimeSessionId": session_id,
            },
            separators=(",", ":"),
        ).encode("utf-8"),
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
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc

    events: list[dict[str, Any]] = []
    for line in text.splitlines():
        if not line.startswith("data:"):
            continue
        raw = line.split("data:", 1)[1].strip()
        if not raw:
            continue
        try:
            events.append(json.loads(raw))
        except json.JSONDecodeError:
            events.append({"data": raw})
    for event in events:
        if event.get("status") == "error":
            raise RuntimeError(str(event.get("error") or "AgentCore returned an error"))
    return events


def agent_text(events: list[dict[str, Any]]) -> str:
    chunks: list[str] = []
    for event in events:
        data = event.get("data")
        if isinstance(data, str):
            chunks.append(data)
        delta = event.get("delta")
        if isinstance(delta, dict) and isinstance(delta.get("text"), str):
            chunks.append(delta["text"])
    return "".join(chunks).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack-name", default=os.environ.get("STACK_NAME"))
    parser.add_argument("--username", default=os.environ.get("SMOKE_COGNITO_USERNAME", ""))
    parser.add_argument("--prompt", required=True)
    args = parser.parse_args()

    username = args.username or input("Cognito username: ").strip()
    password = os.environ.get("SMOKE_COGNITO_PASSWORD") or getpass.getpass("Cognito password: ")
    stack = get_stack_config(args.stack_name)
    outputs = stack["outputs"]
    region = stack["region"]
    auth = authenticate(outputs["CognitoClientId"], region, username, password)
    events = invoke(outputs["RuntimeArn"], region, auth["accessToken"], args.prompt)
    text = agent_text(events)
    print(
        json.dumps(
            {
                "region": region,
                "runtimeArn": outputs["RuntimeArn"],
                "userId": auth["userId"],
                "eventCount": len(events),
                "responsePreview": text[:2000],
                "lastEvents": events[-3:],
            },
            indent=2,
            default=str,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
