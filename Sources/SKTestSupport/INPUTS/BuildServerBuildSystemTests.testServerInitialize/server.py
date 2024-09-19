from pathlib import Path
import sys

sys.path.append(str(Path(__file__).parent.parent))

from AbstractBuildServer import AbstractBuildServer


class BuildServer(AbstractBuildServer):
    pass


BuildServer().run()
