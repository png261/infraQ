import base64
import json
import os
import time
import uuid

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


def handler(event, context):
    bucket_name = os.environ["BUCKET_NAME"]
    table_name = os.environ["TABLE_NAME"]
    cat_id = str(uuid.uuid4())
    body = event.get("body") or ""

    if event.get("isBase64Encoded"):
        image_bytes = base64.b64decode(body)
    else:
        image_bytes = body.encode("utf-8")

    key = f"cats/{cat_id}.jpg"
    s3.put_object(Bucket=bucket_name, Key=key, Body=image_bytes, ContentType="image/jpeg")

    dynamodb.Table(table_name).put_item(Item={"cat_id": cat_id, "s3_key": key, "created_at": str(int(time.time()))})

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"cat_id": cat_id, "key": key}),
    }
