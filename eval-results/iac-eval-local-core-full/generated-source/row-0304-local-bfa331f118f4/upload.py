import base64
import json
import os
import time
import uuid

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


def lambda_handler(event, context):
    bucket_name = os.environ["BUCKET_NAME"]
    table_name = os.environ["TABLE_NAME"]
    table = dynamodb.Table(table_name)

    picture_id = str(uuid.uuid4())
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        picture_bytes = base64.b64decode(body)
    else:
        picture_bytes = body.encode("utf-8")

    key = f"cats/{picture_id}.jpg"
    s3.put_object(Bucket=bucket_name, Key=key, Body=picture_bytes, ContentType="image/jpeg")
    table.put_item(Item={"picture_id": picture_id, "s3_key": key, "created_at": int(time.time())})

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"picture_id": picture_id, "s3_key": key}),
    }
