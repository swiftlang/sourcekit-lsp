#!/usr/bin/env python

import json
import os
import sys


def send(data):
    dataStr = json.dumps(data)
    try:
        sys.stdout.write("Content-Length: {}\r\n\r\n{}".format(len(dataStr), dataStr))
        sys.stdout.flush()
    except IOError:
        # stdout closed, time to quit
        raise SystemExit(0)


while True:
    line = sys.stdin.readline()
    if len(line) == 0:
        break

    assert line.startswith('Content-Length:')
    length = int(line[len('Content-Length:'):])
    sys.stdin.readline()
    message = json.loads(sys.stdin.read(length))

    response = None
    notification = None

    if message["method"] == "build/initialize":
        response = {
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "displayName": "test server",
                "version": "0.1",
                "bspVersion": "2.0",
                "rootUri": "blah",
                "capabilities": {"languageIds": ["a", "b"]},
                "data": {
                    "indexStorePath": "some/index/store/path"
                }
            }
        }
    elif message["method"] == "build/initialized":
        continue
    elif message["method"] == "build/shutdown":
        response = {
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": None
        }
    elif message["method"] == "build/exit":
        break
    elif message["method"] == "textDocument/registerForChanges":
        response = {
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": None
        }
        if message["params"]["action"] == "register":
            notification = {
                "jsonrpc": "2.0",
                "method": "buildTarget/didChange",
                "params": {
                    "changes": [
                        {
                            "target": {"uri": "build://target/a"},
                            "kind": 1,
                            "data": {"key": "value"}
                        }
                    ]
                }
            }

    # ignore other notifications
    elif "id" in message:
        response = {
            "jsonrpc": "2.0",
            "id": message["id"],
            "error": {
                "code": -32600,
                "message": "unhandled method {}".format(message["method"]),
            }
        }

    if response: send(response)
    if notification: send(notification)
