import json


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    method = http.get("method")
    path = event.get("rawPath", "/")

    if method == "GET" and path == "/":
        return _response(200, {"message": "Hello World!"})

    if method == "GET" and path == "/health":
        return _response(200, {"status": "ok"})

    if method == "POST" and path == "/echo":
        try:
            payload = json.loads(event.get("body") or "{}")
        except json.JSONDecodeError:
            return _response(400, {"error": "Invalid JSON"})
        return _response(200, {"received": payload})

    return _response(404, {"error": "Not found"})
