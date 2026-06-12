# coding: utf-8
"""Validate required speech model files before starting the server."""

import sys
from pathlib import Path

from config_server import ModelDownloadLinks, ModelPaths
from config_server import ServerConfig as Config
from util.common.lifecycle import lifecycle
from util.server.server_cosmic import console

from . import logger


def _fail(message: str) -> None:
    logger.error(message)
    console.print(message, style="bright_red")
    lifecycle.cleanup()
    raise SystemExit(1)


def _format_missing_file(path: Path) -> str:
    try:
        return str(path.resolve())
    except OSError:
        return str(path)


def check_model() -> None:
    """Check the configured model files exist on disk."""

    model_type = Config.model_type.lower()
    logger.debug("Checking model files for type: %s", model_type)

    if model_type == "fun_asr_nano":
        required_files = {
            "Fun-ASR-Nano-GGUF": [
                ModelPaths.fun_asr_nano_gguf_encoder_adaptor,
                ModelPaths.fun_asr_nano_gguf_ctc,
                ModelPaths.fun_asr_nano_gguf_llm_decode,
                ModelPaths.fun_asr_nano_gguf_token,
            ]
        }
    elif model_type == "sensevoice":
        required_files = {
            "SenseVoice": [
                ModelPaths.sensevoice_model,
                ModelPaths.sensevoice_tokens,
            ]
        }
    elif model_type == "paraformer":
        required_files = {
            "Paraformer": [
                ModelPaths.paraformer_model,
                ModelPaths.paraformer_tokens,
            ],
            "Punctuation": [
                ModelPaths.punc_model_dir,
            ],
        }
    else:
        _fail(
            "Unsupported model type: "
            f"{Config.model_type}\n"
            "Please set ServerConfig.model_type to one of: "
            "fun_asr_nano, sensevoice, paraformer."
        )

    missing_files: list[tuple[str, Path]] = []
    for category, files in required_files.items():
        for file_path in files:
            if not file_path.exists():
                missing_files.append((category, file_path))
                logger.warning("Missing model file: %s", _format_missing_file(file_path))

    if missing_files:
        lines = [
            "Required speech model files were not found.",
            "",
            f"Configured model type: {model_type}",
            f"Model root: {_format_missing_file(ModelPaths.model_dir)}",
            "",
        ]
        for category, file_path in missing_files:
            lines.append(f"[{category}] {_format_missing_file(file_path)}")
        lines.extend(
            [
                "",
                f"Download page: {ModelDownloadLinks.models_page}",
            ]
        )
        _fail("\n".join(lines))

    logger.info("Model file check passed (%s)", model_type)
    console.print(f"[green4]Model file check passed ({model_type})", end="\n\n")
