#!/usr/bin/env python

import json
import sys


while True:
    line = sys.stdin.readline()
    if len(line) == 0:
        break

    assert line.startswith('Content-Length:')
    length = int(line[len('Content-Length:'):])
    sys.stdin.readline()
    message = json.loads(sys.stdin.read(length))

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
                    "index_store_path": "some/index/store/path"
                }
            }
        }
    else:
        response = {
            "jsonrpc": "2.0",
            "id": message["id"],
            "error": {
                "code": 123,
                "message": "unhandled method",
            }
        }

    responseStr = json.dumps(response)
    sys.stdout.write("Content-Length: {}\r\n\r\n{}".format(len(responseStr), responseStr))
    sys.stdout.flush()

