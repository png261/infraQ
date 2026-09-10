import json
import os


def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "cat update endpoint",
            "bucket": os.environ.get("CAT_BUCKET"),
            "table": os.environ.get("CAT_TABLE"),
        }),
    }
