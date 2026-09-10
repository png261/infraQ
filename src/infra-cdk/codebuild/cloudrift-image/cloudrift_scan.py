import json
import os
import shutil
import subprocess
import time
import traceback

import boto3

control_sm = boto3.client("secretsmanager")
control_sns = boto3.client("sns")
control_ddb = boto3.resource("dynamodb")
table = control_ddb.Table(os.environ["RESOURCES_TABLE_NAME"])

user_id = os.environ["USER_ID"]
job_mode = os.environ.get("JOB_MODE", "scan")
scan_id = os.environ.get("SCAN_ID", "")
backend_id = os.environ["BACKEND_ID"]
backend_name = os.environ.get("BACKEND_NAME", "")
state_bucket = os.environ.get("STATE_BUCKET", "")
state_key = os.environ.get("STATE_KEY", "")
state_region = os.environ.get("STATE_REGION") or os.environ.get("AWS_REGION") or "ap-southeast-1"
scan_service = (os.environ.get("SCAN_SERVICE") or "s3").lower()
drift_guard_id = os.environ.get("DRIFT_GUARD_ID", "")
alert_topic_arn = os.environ.get("ALERT_TOPIC_ARN", "")
started_at = os.environ.get("SCAN_STARTED_AT") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def normalize_list(value):
    if isinstance(value, list):
        return value
    if value in (None, ""):
        return []
    return [value]

def is_collection_section(value):
    return isinstance(value, list) or isinstance(value, dict)

def pick_scan_sections(payload):
    if isinstance(payload, list):
        return [], [], payload
    if not isinstance(payload, dict):
        return [], [], []

    drift = normalize_list(payload.get("drifts") or payload.get("drift") or payload.get("drift_alerts"))
    policies = []
    policy_result = payload.get("policy_result")
    if isinstance(policy_result, dict):
        policies.extend(normalize_list(policy_result.get("violations")))
        policies.extend(normalize_list(policy_result.get("warnings")))
    policies.extend(normalize_list(payload.get("policy_alerts") or payload.get("policy_violations")))
    resources = normalize_list(
        payload.get("resources") or payload.get("current_resources") or payload.get("inventory")
    )
    for key, value in payload.items():
        lowered = key.lower()
        if key in ("drifts", "drift", "drift_alerts"):
            continue
        if key in ("policy_result", "policy_alerts", "policy_violations"):
            continue
        if key in ("resources", "current_resources", "inventory"):
            continue
        if is_collection_section(value) and "drift" in lowered:
            drift.extend(normalize_list(value))
        elif is_collection_section(value) and ("policy" in lowered or "issue" in lowered or "alert" in lowered or "violation" in lowered):
            policies.extend(normalize_list(value))
        elif is_collection_section(value) and ("resource" in lowered or "current" in lowered or "inventory" in lowered):
            resources.extend(normalize_list(value))

    if not drift and not policies and not resources:
        resources = [payload]
    return drift, policies, resources

def parse_cloudrift_json(stdout):
    text = stdout or "{}"
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    marker = text.rfind("\n{")
    if marker >= 0:
        candidate = text[marker + 1 :]
    else:
        marker = text.find("{")
        candidate = text[marker:] if marker >= 0 else "{}"
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        return {"output": text}

def store(status, drift=None, policies=None, resources=None, raw=None, error=None):
    existing = table.get_item(Key={"pk": user_id, "sk": "SCAN#" + scan_id}).get("Item", {})
    item = {
        "pk": user_id,
        "sk": "SCAN#" + scan_id,
        "type": "scan",
        "scanId": scan_id,
        "backendId": backend_id,
        "backendName": backend_name,
        "stateBucket": state_bucket,
        "stateKey": state_key,
        "stateRegion": state_region,
        "service": scan_service,
        "status": status,
        "startedAt": started_at,
        "updatedAt": now(),
        "driftAlerts": drift or [],
        "policyAlerts": policies or [],
        "currentResources": resources or [],
    }
    if raw is not None:
        item["rawResult"] = raw
    if existing.get("graphBucket"):
        item["graphBucket"] = existing["graphBucket"]
    if existing.get("graphKey"):
        item["graphKey"] = existing["graphKey"]
    if existing.get("graphGeneratedAt"):
        item["graphGeneratedAt"] = existing["graphGeneratedAt"]
    if existing.get("graphError"):
        item["graphError"] = existing["graphError"]
    if error:
        item["error"] = str(error)[:4000]
    if existing.get("codeBuildBuildId"):
        item["codeBuildBuildId"] = existing["codeBuildBuildId"]
    if existing.get("repository"):
        item["repository"] = existing["repository"]
    if drift_guard_id:
        item["guardId"] = drift_guard_id
    table.put_item(Item=item)

def publish_scan_alert(drift, policies):
    drift_count = len(drift or [])
    policy_count = len(policies or [])
    if not alert_topic_arn or (not drift_count and not policy_count):
        return
    if drift_count and policy_count:
        alert_type = "drift and policy findings"
    elif drift_count:
        alert_type = "drift detected"
    else:
        alert_type = "policy findings detected"
    subject = "Cloudrift {}: {}".format(alert_type, backend_name or backend_id)
    message = {
        "backendName": backend_name,
        "backendId": backend_id,
        "scanId": scan_id,
        "state": "s3://{}/{}".format(state_bucket, state_key),
        "region": state_region,
        "service": scan_service,
        "alertType": alert_type,
        "driftCount": drift_count,
        "policyCount": policy_count,
        "startedAt": started_at,
        "updatedAt": now(),
    }
    control_sns.publish(
        TopicArn=alert_topic_arn,
        Subject=subject[:100],
        Message=json.dumps(message, indent=2, default=str),
    )

def store_tf_job(status, phase, error=None):
    job_id = os.environ["PLAN_JOB_ID"]
    expression = "SET #status = :status, phase = :phase, updatedAt = :updatedAt"
    names = {"#status": "status"}
    values = {
        ":status": status,
        ":phase": phase,
        ":updatedAt": now(),
    }
    if error:
        expression += ", #error = :error"
        names["#error"] = "error"
        values[":error"] = str(error)[:4000]
    table.update_item(
        Key={"pk": user_id, "sk": "TFJOB#" + job_id},
        UpdateExpression=expression,
        ExpressionAttributeNames=names,
        ExpressionAttributeValues=values,
    )

def run_checked(command, phase, env):
    store_tf_job("RUNNING", phase)
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        env=env,
        timeout=900,
    )
    if completed.returncode != 0:
        message = completed.stderr or completed.stdout or "{} failed".format(phase)
        store_tf_job("FAILED", phase, message)
        raise RuntimeError(message)
    return completed

def state_to_plan(state_payload):
    if isinstance(state_payload, dict) and isinstance(state_payload.get("resource_changes"), list):
        return state_payload
    if not isinstance(state_payload, dict):
        return {"resource_changes": []}

    changes = []
    for resource in state_payload.get("resources", []):
        if not isinstance(resource, dict):
            continue
        if resource.get("mode") != "managed":
            continue
        resource_type = resource.get("type")
        if scan_service == "s3" and resource_type != "aws_s3_bucket":
            continue
        if scan_service == "ec2" and resource_type not in (
            "aws_instance",
            "aws_security_group",
            "aws_security_group_rule",
            "aws_vpc_security_group_ingress_rule",
            "aws_vpc_security_group_egress_rule",
        ):
            continue
        if scan_service == "iam" and not str(resource_type or "").startswith("aws_iam_"):
            continue
        for index, instance in enumerate(resource.get("instances", [])):
            if not isinstance(instance, dict):
                continue
            attributes = instance.get("attributes")
            if not isinstance(attributes, dict):
                continue
            address = resource.get("address")
            if not address:
                address = "{}.{}".format(resource.get("type", "resource"), resource.get("name", index))
            changes.append(
                {
                    "address": address,
                    "type": resource.get("type"),
                    "name": resource.get("name", str(index)),
                    "change": {
                        "actions": ["no-op"],
                        "after": attributes,
                    },
                }
            )
    return {"resource_changes": changes}

def plan_after(resource):
    if not isinstance(resource, dict):
        return {}
    change = resource.get("change")
    if isinstance(change, dict) and isinstance(change.get("after"), dict):
        return change["after"]
    if isinstance(resource.get("values"), dict):
        return resource["values"]
    return {}

def add_plan_index_key(index, key, resource):
    current = str(key or "").strip()
    if current and current not in index:
        index[current] = resource

def build_plan_index(plan_payload):
    index = {}
    for resource in normalize_list(plan_payload.get("resource_changes") if isinstance(plan_payload, dict) else []):
        if not isinstance(resource, dict):
            continue
        after = plan_after(resource)
        add_plan_index_key(index, resource.get("address"), resource)
        add_plan_index_key(index, resource.get("name"), resource)
        for key in ("id", "bucket", "bucket_prefix", "arn", "name"):
            add_plan_index_key(index, after.get(key), resource)
        tags = after.get("tags")
        if isinstance(tags, dict):
            add_plan_index_key(index, tags.get("Name"), resource)
    return index

def plan_resource_for_alert(alert, plan_index):
    if not isinstance(alert, dict):
        return None
    for key in ("resource_address", "address", "resource_id", "resource_name", "name"):
        resource = plan_index.get(str(alert.get(key) or "").strip())
        if resource:
            return resource
    return None

def is_cloudrift_placeholder(value):
    current = str(value or "").strip().lower()
    return current in ("<planned>", "<actual>", "planned", "actual")

def normalize_diff_pair(value):
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return [value[0], value[1]]
    if isinstance(value, dict):
        return [
            value.get("expected", value.get("before", value.get("planned", value.get("desired")))),
            value.get("actual", value.get("after", value.get("current", value.get("live")))),
        ]
    return [None, None]

def values_differ(before, after):
    return before != after

def diff_value_rows(before, after, prefix=""):
    if isinstance(before, dict) and isinstance(after, dict):
        rows = []
        for key in sorted(set(before.keys()) | set(after.keys())):
            current = "{}.{}".format(prefix, key) if prefix else str(key)
            rows.extend(diff_value_rows(before.get(key), after.get(key), current))
        return rows
    if values_differ(before, after):
        return [{"attribute": prefix or "value", "expected": before, "actual": after}]
    return []

def refresh_drift_rows(refresh_payload):
    rows = []
    for resource in normalize_list(refresh_payload.get("resource_drift") if isinstance(refresh_payload, dict) else []):
        if not isinstance(resource, dict):
            continue
        change = resource.get("change")
        if not isinstance(change, dict):
            continue
        before = change.get("before")
        after = change.get("after")
        for row in diff_value_rows(before, after):
            rows.append(
                {
                    "resource_address": resource.get("address"),
                    "resource_type": resource.get("type"),
                    "resource_name": resource.get("name"),
                    "attribute": row["attribute"],
                    "expected": row["expected"],
                    "actual": row["actual"],
                }
            )
    return rows

def build_refresh_index(refresh_rows):
    index = {}
    for row in refresh_rows:
        for key in ("resource_address", "resource_name"):
            value = str(row.get(key) or "").strip()
            if value:
                index.setdefault(value, []).append(row)
    return index

def refresh_rows_for_alert(alert, refresh_index):
    if not isinstance(alert, dict):
        return []
    rows = []
    seen = set()
    for key in ("resource_address", "address", "resource_id", "resource_name", "name"):
        value = str(alert.get(key) or "").strip()
        for row in refresh_index.get(value, []):
            marker = (row.get("resource_address"), row.get("attribute"))
            if marker not in seen:
                rows.append(row)
                seen.add(marker)
    return rows

def refresh_alerts(refresh_rows):
    grouped = {}
    for row in refresh_rows:
        address = row.get("resource_address") or row.get("resource_name") or "terraform_refresh"
        current = grouped.setdefault(
            address,
            {
                "resource_address": row.get("resource_address"),
                "resource_type": row.get("resource_type"),
                "resource_name": row.get("resource_name"),
                "resource_id": row.get("resource_name") or row.get("resource_address"),
                "severity": "warning",
                "message": "Terraform refresh detected live infrastructure drift",
                "source": "terraform_refresh",
                "missing": False,
                "diffs": {},
                "expected_attributes": {},
                "actual_attributes": {},
            },
        )
        attribute = row.get("attribute") or "value"
        current["diffs"][attribute] = [row.get("expected"), row.get("actual")]
        current["expected_attributes"][attribute] = row.get("expected")
        current["actual_attributes"][attribute] = row.get("actual")
    return list(grouped.values())

def prepare_refresh_source(s3_client, backend_item):
    source_prefix = str((backend_item or {}).get("sourcePrefix") or os.environ.get("SOURCE_PREFIX") or "").strip().rstrip("/")
    if os.path.isdir("terraform-src"):
        shutil.rmtree("terraform-src")
    os.makedirs("terraform-src", exist_ok=True)
    found = False
    if source_prefix:
        paginator = s3_client.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=state_bucket, Prefix=source_prefix + "/"):
            for obj in page.get("Contents", []):
                key = obj.get("Key", "")
                if key.endswith("/"):
                    continue
                name = key.rsplit("/", 1)[-1]
                if not (name.endswith(".tf") or name.endswith(".tfvars")):
                    continue
                s3_client.download_file(state_bucket, key, os.path.join("terraform-src", name))
                found = True
        if found:
            return True
    repository = (backend_item or {}).get("repository")
    repo_url = repository.get("url") if isinstance(repository, dict) else ""
    if repo_url:
        shutil.rmtree("terraform-src", ignore_errors=True)
        default_branch = str(repository.get("defaultBranch") or repository.get("default_branch") or "").strip()
        clone_command = ["git", "clone", "--depth", "1"]
        if default_branch:
            clone_command.extend(["--branch", default_branch])
        clone_command.extend([repo_url, "terraform-src"])
        completed = subprocess.run(
            clone_command,
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )
        return completed.returncode == 0
    return False

def run_terraform_refresh(s3_client, env):
    backend_item = table.get_item(Key={"pk": user_id, "sk": "BACKEND#" + backend_id}).get("Item", {})
    if not prepare_refresh_source(s3_client, backend_item):
        return None, "No Terraform source files available for refresh-only plan"
    backend_tf = os.path.join("terraform-src", "backend.tf")
    with open(backend_tf, "w", encoding="utf-8") as backend_file:
        backend_file.write('terraform {\n  backend "s3" {}\n}\n')
    init = subprocess.run(
        [
            "terraform",
            "-chdir=terraform-src",
            "init",
            "-input=false",
            "-backend-config=bucket=" + state_bucket,
            "-backend-config=key=" + state_key,
            "-backend-config=region=" + state_region,
        ],
        check=False,
        capture_output=True,
        text=True,
        env=env,
        timeout=900,
    )
    if init.returncode != 0:
        return None, init.stderr or init.stdout or "terraform init failed"
    plan = subprocess.run(
        ["terraform", "-chdir=terraform-src", "plan", "-refresh-only", "-input=false", "-out=refresh.tfplan"],
        check=False,
        capture_output=True,
        text=True,
        env=env,
        timeout=900,
    )
    if plan.returncode != 0:
        return None, plan.stderr or plan.stdout or "terraform refresh-only plan failed"
    show = subprocess.run(
        ["terraform", "-chdir=terraform-src", "show", "-json", "refresh.tfplan"],
        check=False,
        capture_output=True,
        text=True,
        env=env,
        timeout=300,
    )
    if show.returncode != 0:
        return None, show.stderr or show.stdout or "terraform show failed"
    return json.loads(show.stdout), None

def dict_or_empty(value):
    return value if isinstance(value, dict) else {}

def nested_value(record, attribute):
    if not isinstance(record, dict):
        return None
    if attribute in record:
        return record.get(attribute)
    current = record
    for part in str(attribute or "").split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current.get(part)
    return current

def first_known_value(*values):
    for value in values:
        if value is None or value == "":
            continue
        if is_cloudrift_placeholder(value):
            continue
        return value
    return None

def attribute_from_records(attribute, *records):
    for record in records:
        value = nested_value(dict_or_empty(record), attribute)
        if value is not None and value != "":
            return value
    return None

def enrich_drift_alert(alert, plan_resource, refresh_index):
    if not isinstance(alert, dict):
        return alert
    after = plan_after(plan_resource)
    diffs = alert.get("diffs")
    if not isinstance(diffs, dict):
        return alert
    enriched = dict(alert)
    new_diffs = {}
    expected_attributes = dict(dict_or_empty(enriched.get("expected_attributes")))
    actual_attributes = dict(dict_or_empty(enriched.get("actual_attributes")))
    planned_attrs = dict_or_empty(enriched.get("planned_attributes"))
    state_attrs = dict_or_empty(enriched.get("state_attributes"))
    current_attrs = dict_or_empty(enriched.get("current_attributes"))
    live_attrs = dict_or_empty(enriched.get("live_attributes"))
    extra_attrs = dict_or_empty(enriched.get("extra_attributes"))
    refresh_rows = refresh_rows_for_alert(enriched, refresh_index)
    refresh_by_attribute = {row.get("attribute"): row for row in refresh_rows}
    for attribute, value in diffs.items():
        raw_expected, raw_actual = normalize_diff_pair(value)
        had_placeholder = is_cloudrift_placeholder(raw_expected) or is_cloudrift_placeholder(raw_actual)
        refresh_row = refresh_by_attribute.get(attribute)
        expected = first_known_value(
            raw_expected,
            refresh_row.get("expected") if refresh_row else None,
            attribute_from_records(attribute, expected_attributes, planned_attrs, state_attrs, after),
        )
        actual = first_known_value(
            raw_actual,
            refresh_row.get("actual") if refresh_row else None,
            attribute_from_records(attribute, actual_attributes, current_attrs, live_attrs, extra_attrs),
            "missing from AWS" if enriched.get("missing") else None,
        )
        if had_placeholder and expected is None:
            expected = "not returned by Cloudrift"
        if had_placeholder and actual is None:
            actual = "not returned by Cloudrift"
        if expected is not None or actual is not None:
            new_diffs[attribute] = [expected, actual]
            if expected is not None:
                expected_attributes[attribute] = expected
            if actual is not None:
                actual_attributes[attribute] = actual
        else:
            new_diffs[attribute] = value
    enriched["diffs"] = new_diffs
    if expected_attributes:
        enriched["expected_attributes"] = expected_attributes
    if actual_attributes:
        enriched["actual_attributes"] = actual_attributes
    if refresh_rows:
        enriched["terraform_refresh_diffs"] = refresh_rows
    return enriched

def enrich_drift_alerts(drift, plan_payload, refresh_payload=None):
    plan_index = build_plan_index(plan_payload)
    refresh_rows = refresh_drift_rows(refresh_payload or {})
    refresh_index = build_refresh_index(refresh_rows)
    enriched = []
    for alert in normalize_list(drift):
        if not isinstance(alert, dict):
            enriched.append(alert)
            continue
        plan_resource = plan_resource_for_alert(alert, plan_index)
        enriched.append(enrich_drift_alert(alert, plan_resource, refresh_index))
    existing_addresses = {str(alert.get("resource_address") or alert.get("address") or "").strip() for alert in enriched if isinstance(alert, dict)}
    for alert in refresh_alerts(refresh_rows):
        address = str(alert.get("resource_address") or "").strip()
        if address and address not in existing_addresses:
            enriched.append(alert)
            existing_addresses.add(address)
    return enriched

def normalize_security_group_rules(value):
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        return [value]
    return []

def rule_allows_public_ssh(rule):
    if not isinstance(rule, dict):
        return False
    protocol = str(rule.get("protocol") or rule.get("ip_protocol") or rule.get("IpProtocol") or "").lower()
    from_port = rule.get("from_port", rule.get("FromPort"))
    to_port = rule.get("to_port", rule.get("ToPort"))
    cidrs = []
    for key in ("cidr_blocks", "cidr_ipv4", "CidrIpv4"):
        current = rule.get(key)
        if isinstance(current, list):
            cidrs.extend(str(item) for item in current)
        elif current:
            cidrs.append(str(current))
    for ip_range in normalize_security_group_rules(rule.get("ip_ranges") or rule.get("IpRanges")):
        if ip_range.get("CidrIp"):
            cidrs.append(str(ip_range.get("CidrIp")))
    try:
        from_port = int(from_port)
        to_port = int(to_port)
    except (TypeError, ValueError):
        return False
    return protocol in ("tcp", "6", "-1", "all") and from_port <= 22 <= to_port and "0.0.0.0/0" in cidrs

def synthesize_security_group_policy_alerts(drift):
    alerts = []
    seen = set()
    for alert in normalize_list(drift):
        if not isinstance(alert, dict) or alert.get("resource_type") != "aws_security_group":
            continue
        actual_attributes = dict_or_empty(alert.get("actual_attributes"))
        diffs = dict_or_empty(alert.get("diffs"))
        candidates = []
        candidates.extend(normalize_security_group_rules(actual_attributes.get("ingress")))
        ingress_diff = diffs.get("ingress")
        if isinstance(ingress_diff, (list, tuple)) and len(ingress_diff) >= 2:
            candidates.extend(normalize_security_group_rules(ingress_diff[1]))
        for rule in candidates:
            if not rule_allows_public_ssh(rule):
                continue
            marker = (alert.get("resource_address"), "CKV_AWS_25")
            if marker in seen:
                continue
            seen.add(marker)
            alerts.append(
                {
                    "resource": alert.get("resource_address") or alert.get("resource_name") or alert.get("resource_id"),
                    "resource_type": "aws_security_group",
                    "resource_id": alert.get("resource_id") or alert.get("resource_name"),
                    "type": "policy_violation",
                    "policy_id": "CKV_AWS_25",
                    "description": "Security group allows SSH ingress from 0.0.0.0/0",
                    "severity": "critical",
                    "framework": ["SOC2", "PCI-DSS"],
                    "source": "terraform_refresh",
                    "rule": rule,
                }
            )
    return alerts

try:
    secret_value = control_sm.get_secret_value(SecretId=os.environ["AWS_CREDENTIAL_SECRET_ID"])
    credential_store = json.loads(secret_value.get("SecretString") or "{}")
    if isinstance(credential_store.get("credentials"), dict):
        credential_id = os.environ.get("AWS_CREDENTIAL_ID") or credential_store.get("activeCredentialId")
        secret = credential_store["credentials"].get(credential_id) or {}
    else:
        secret = credential_store
    if not secret.get("accessKeyId") or not secret.get("secretAccessKey"):
        raise RuntimeError("Selected AWS credential was not found")
    env = os.environ.copy()
    env["AWS_ACCESS_KEY_ID"] = secret["accessKeyId"]
    env["AWS_SECRET_ACCESS_KEY"] = secret["secretAccessKey"]
    if secret.get("sessionToken"):
        env["AWS_SESSION_TOKEN"] = secret["sessionToken"]
    env["AWS_DEFAULT_REGION"] = state_region
    env["AWS_REGION"] = state_region
    env["TF_STATE_BUCKET"] = state_bucket
    env["TF_STATE_KEY"] = state_key

    session_kwargs = {
        "aws_access_key_id": secret["accessKeyId"],
        "aws_secret_access_key": secret["secretAccessKey"],
        "region_name": state_region,
    }
    if secret.get("sessionToken"):
        session_kwargs["aws_session_token"] = secret["sessionToken"]
    target_session = boto3.Session(**session_kwargs)
    if job_mode == "terraform_plan":
        s3_client = target_session.client("s3")
        source_prefix = os.environ["SOURCE_PREFIX"].rstrip("/") + "/"
        os.makedirs("terraform-src", exist_ok=True)
        paginator = s3_client.get_paginator("list_objects_v2")
        found = False
        for page in paginator.paginate(Bucket=state_bucket, Prefix=source_prefix):
            for obj in page.get("Contents", []):
                key = obj.get("Key", "")
                if key.endswith("/"):
                    continue
                name = key.rsplit("/", 1)[-1]
                if not (name.endswith(".tf") or name.endswith(".tfvars")):
                    continue
                s3_client.download_file(state_bucket, key, os.path.join("terraform-src", name))
                found = True
        if not found:
            store_tf_job("FAILED", "download", "No Terraform files found")
            raise RuntimeError("No Terraform files found")
        run_checked(["terraform", "-chdir=terraform-src", "init", "-input=false"], "init", env)
        run_checked(["terraform", "-chdir=terraform-src", "plan", "-input=false", "-out=tfplan"], "plan", env)
        show = run_checked(["terraform", "-chdir=terraform-src", "show", "-json", "tfplan"], "show", env)
        json.loads(show.stdout)
        s3_client.put_object(
            Bucket=state_bucket,
            Key=state_key,
            Body=show.stdout.encode("utf-8"),
            ContentType="application/json",
        )
        timestamp = now()
        table.update_item(
            Key={"pk": user_id, "sk": "BACKEND#" + backend_id},
            UpdateExpression="SET updatedAt = :updatedAt, planUpdatedAt = :planUpdatedAt",
            ExpressionAttributeValues={":updatedAt": timestamp, ":planUpdatedAt": timestamp},
        )
        store_tf_job("SUCCEEDED", "show")
        raise SystemExit(0)

    s3_client = target_session.client("s3")
    s3_client.download_file(state_bucket, state_key, "terraform-state.json")
    with open("terraform-state.json", "r", encoding="utf-8") as state_file:
        state_payload = json.load(state_file)
    plan_payload = state_to_plan(state_payload)
    refresh_payload, refresh_error = run_terraform_refresh(s3_client, env)
    with open("plan.json", "w", encoding="utf-8") as plan_file:
        json.dump(plan_payload, plan_file)
    with open("cloudrift.yml", "w", encoding="utf-8") as config_file:
        config_file.write("region: {}\n".format(state_region))
        config_file.write("plan_path: ./plan.json\n")

    completed = subprocess.run(
        ["cloudrift", "scan", "--config=cloudrift.yml", "--service=" + scan_service, "--format=json"],
        check=False,
        capture_output=True,
        text=True,
        env=env,
        timeout=900,
    )
    if completed.returncode != 0:
        store("FAILED", error=(completed.stderr or completed.stdout or "Cloudrift scan failed"))
        raise SystemExit(completed.returncode)

    payload = parse_cloudrift_json(completed.stdout)

    drift, policies, resources = pick_scan_sections(payload)
    drift = [alert for alert in drift if isinstance(alert, dict)]
    policies = [alert for alert in policies if isinstance(alert, dict)]
    drift = enrich_drift_alerts(drift, plan_payload, refresh_payload)
    policies.extend(synthesize_security_group_policy_alerts(drift))
    if isinstance(payload, dict):
        if refresh_payload is not None:
            payload["terraform_refresh"] = {
                "resource_drift_count": len(normalize_list(refresh_payload.get("resource_drift"))),
                "resource_drift": normalize_list(refresh_payload.get("resource_drift")),
            }
        if refresh_error:
            payload["terraform_refresh_error"] = str(refresh_error)[:4000]
        for key in ("drifts", "drift_alerts"):
            if isinstance(payload.get(key), list):
                payload[key] = drift
    resources = [resource for resource in resources if isinstance(resource, dict)]
    if not resources:
        resources = normalize_list(plan_payload.get("resource_changes"))
    store("SUCCEEDED", drift=drift, policies=policies, resources=resources, raw=payload)
    publish_scan_alert(drift, policies)
except Exception as exc:
    store("FAILED", error="{}\n{}".format(exc, traceback.format_exc()))
    raise
