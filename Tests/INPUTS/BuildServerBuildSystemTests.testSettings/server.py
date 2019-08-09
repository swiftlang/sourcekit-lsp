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

    # create fixed reply
    response = {
        "jsonrpc": "2.0",
        "id": message["id"],
        "result": {
            "flags": ["a", "b"]
        }
    }
    responseStr = json.dumps(response)
    sys.stdout.write("Content-Length: {}\r\n\r\n{}".format(len(responseStr), responseStr))
    sys.stdout.flush()

