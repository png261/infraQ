import json
import os
import random

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


def handler(event, context):
    bucket_name = os.environ["BUCKET_NAME"]
    table_name = os.environ["TABLE_NAME"]

    response = dynamodb.Table(table_name).scan(ProjectionExpression="cat_id, s3_key")
    items = response.get("Items", [])
    if not items:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "No cat pictures have been uploaded yet."}),
        }

    cat = random.choice(items)
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket_name, "Key": cat["s3_key"]},
        ExpiresIn=300,
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"cat_id": cat["cat_id"], "url": url}),
    }
