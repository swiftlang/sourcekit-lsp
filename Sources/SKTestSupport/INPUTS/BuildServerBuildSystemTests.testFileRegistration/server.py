from pathlib import Path
import sys

sys.path.append(str(Path(__file__).parent.parent))

from AbstractBuildServer import AbstractBuildServer


class BuildServer(AbstractBuildServer):
    def register_for_changes(self, notification: dict[str, object]):
        if notification["action"] == "register":
            self.send_notification(
                "build/sourceKitOptionsChanged",
                {
                    "uri": notification["uri"],
                    "updatedOptions": {
                        "options": ["a", "b"],
                        "workingDirectory": "/some/dir",
                    },
                },
            )


BuildServer().run()
