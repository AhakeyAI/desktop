"""Best-effort restoration for temporary macOS CapsLock remapping."""

from __future__ import annotations

import subprocess
import sys


def restore_capslock_mapping_best_effort() -> bool:
    """Clear temporary hidutil remaps so CapsLock/input-source switching works again."""
    if sys.platform != "darwin":
        return False

    try:
        subprocess.run(
            ["hidutil", "property", "--set", '{"UserKeyMapping":[]}'],
            capture_output=True,
            check=False,
            timeout=2,
        )
        return True
    except Exception:
        return False
