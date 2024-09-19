from pathlib import Path
import sys

sys.path.append(str(Path(__file__).parent.parent))

from AbstractBuildServer import AbstractBuildServer


class BuildServer(AbstractBuildServer):
    def register_for_changes(self, notification: dict[str, object]):
        if notification["action"] == "register":
            self.send_notification(
                "buildTarget/didChange",
                {
                    "changes": [
                        {
                            "target": {"uri": "build://target/a"},
                            "kind": 1,
                            "data": {"key": "value"},
                        }
                    ]
                },
            )


BuildServer().run()
