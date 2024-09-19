import json
import sys
from typing import Optional


class RequestError(Exception):
    """
    An error that can be thrown from a request handling function in `AbstractBuildServer` to return an error response to
    SourceKit-LSP.
    """

    code: int
    message: str

    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message


class AbstractBuildServer:
    """
    An abstract class to implement a BSP server in Python for SourceKit-LSP testing purposes.
    """

    def run(self):
        """
        Run the build server. This should be called from the top-level code of the build server's Python file.
        """
        while True:
            line = sys.stdin.readline()
            if len(line) == 0:
                break

            assert line.startswith("Content-Length:")
            length = int(line[len("Content-Length:") :])
            sys.stdin.readline()
            message = json.loads(sys.stdin.read(length))

            try:
                result = self.handle_message(message)
                if result:
                    response_message: dict[str, object] = {
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "result": result,
                    }
                    self.send_raw_message(response_message)
            except RequestError as e:
                error_response_message: dict[str, object] = {
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "error": {
                        "code": e.code,
                        "message": e.message,
                    },
                }
                self.send_raw_message(error_response_message)

    def handle_message(self, message: dict[str, object]) -> Optional[dict[str, object]]:
        """
        Dispatch handling of the given method, received from SourceKit-LSP to the message handling function.
        """
        method: str = str(message["method"])
        params: dict[str, object] = message["params"]  # type: ignore
        if method == "build/exit":
            return self.exit(params)
        elif method == "build/initialize":
            return self.initialize(params)
        elif method == "build/initialized":
            return self.initialized(params)
        elif method == "build/shutdown":
            return self.shutdown(params)
        elif method == "textDocument/registerForChanges":
            return self.register_for_changes(params)

        # ignore other notifications
        if "id" in message:
            raise RequestError(code=-32601, message=f"Method not found: {method}")

    def send_raw_message(self, message: dict[str, object]):
        """
        Send a raw message to SourceKit-LSP. The message needs to have all JSON-RPC wrapper fields.

        Subclasses should not call this directly
        """
        message_str = json.dumps(message)
        sys.stdout.buffer.write(
            f"Content-Length: {len(message_str)}\r\n\r\n{message_str}".encode("utf-8")
        )
        sys.stdout.flush()

    def send_notification(self, method: str, params: dict[str, object]):
        """
        Send a notification with the given method and parameters to SourceKit-LSP.
        """
        message: dict[str, object] = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        }
        self.send_raw_message(message)

    # Message handling functions.
    # Subclasses should override these to provide functionality.

    def exit(self, notification: dict[str, object]) -> None:
        pass

    def initialize(self, request: dict[str, object]) -> dict[str, object]:
        return {
            "displayName": "test server",
            "version": "0.1",
            "bspVersion": "2.0",
            "rootUri": "blah",
            "capabilities": {"languageIds": ["a", "b"]},
            "data": {
                "indexDatabasePath": "some/index/db/path",
                "indexStorePath": "some/index/store/path",
            },
        }

    def initialized(self, notification: dict[str, object]) -> None:
        pass

    def register_for_changes(self, notification: dict[str, object]):
        pass

    def shutdown(self, notification: dict[str, object]) -> None:
        pass
