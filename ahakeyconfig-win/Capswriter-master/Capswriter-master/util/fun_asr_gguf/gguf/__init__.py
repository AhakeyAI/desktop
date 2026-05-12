import sys as _sys

# This repository vendors gguf under util.fun_asr_gguf.gguf, but some upstream
# code expects a top-level "gguf" package. Provide an alias so both import
# styles work, especially in PyInstaller one-folder/one-file builds.
_sys.modules.setdefault("gguf", _sys.modules[__name__])

from .constants import *
from .lazy import *
from .gguf_reader import *
from .gguf_writer import *
from .quants import *
from .tensor_mapping import *
from .vocab import *
from .utility import *
from .metadata import *
