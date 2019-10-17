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

    response = None
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
    elif message["method"] == "buildTarget/outputPaths":
        response = {
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "items": [
                    {
                        "target": {"uri": "build://target/a"},
                        "outputPaths": [
                            "file:///path/to/a/file",
                            "file:///path/to/a/file2"
                        ]
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
                "code": 123,
                "message": "unhandled method {}".format(message["method"]),
            }
        }

    if response:
        responseStr = json.dumps(response)
        try:
            sys.stdout.write("Content-Length: {}\r\n\r\n{}".format(len(responseStr), responseStr))
            sys.stdout.flush()
        except IOError:
            # stdout closed, time to quit
            break
