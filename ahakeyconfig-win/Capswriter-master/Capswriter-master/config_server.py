import os
import sys
from pathlib import Path

__version__ = "2.4"


if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

BASE_PATH = Path(BASE_DIR)


class ServerConfig:
    addr = "0.0.0.0"
    port = "6016"

    model_type = "fun_asr_nano"

    format_num = True
    format_spell = True

    enable_tray = True
    log_level = "INFO"


class ModelDownloadLinks:
    models_page = "https://github.com/HaujetZhao/CapsWriter-Offline/releases/tag/models"


class ModelPaths:
    model_dir = BASE_PATH / "models"

    paraformer_dir = (
        model_dir
        / "Paraformer"
        / "speech_paraformer-large-vad-punc_asr_nat-zh-cn-16k-common-vocab8404-onnx"
    )
    paraformer_model = paraformer_dir / "model.onnx"
    paraformer_tokens = paraformer_dir / "tokens.txt"

    punc_model_dir = (
        model_dir
        / "Punct-CT-Transformer"
        / "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12"
        / "model.onnx"
    )

    sensevoice_dir = (
        model_dir
        / "SenseVoice-Small"
        / "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    )
    sensevoice_model = sensevoice_dir / "model.onnx"
    sensevoice_tokens = sensevoice_dir / "tokens.txt"

    fun_asr_nano_gguf_dir = model_dir / "Fun-ASR-Nano" / "Fun-ASR-Nano-GGUF"
    fun_asr_nano_gguf_encoder_adaptor = (
        fun_asr_nano_gguf_dir / "Fun-ASR-Nano-Encoder-Adaptor.int8.onnx"
    )
    fun_asr_nano_gguf_ctc = fun_asr_nano_gguf_dir / "Fun-ASR-Nano-CTC.int8.onnx"
    fun_asr_nano_gguf_llm_decode = (
        fun_asr_nano_gguf_dir / "Fun-ASR-Nano-Decoder.q8_0.gguf"
    )
    fun_asr_nano_gguf_token = fun_asr_nano_gguf_dir / "tokens.txt"
    fun_asr_nano_gguf_hotwords = BASE_PATH / "hot-server.txt"


class ParaformerArgs:
    paraformer = ModelPaths.paraformer_model.as_posix()
    tokens = ModelPaths.paraformer_tokens.as_posix()
    num_threads = 4
    sample_rate = 16000
    feature_dim = 80
    decoding_method = "greedy_search"
    provider = "cpu"
    debug = False


class SenseVoiceArgs:
    model = ModelPaths.sensevoice_model.as_posix()
    tokens = ModelPaths.sensevoice_tokens.as_posix()
    use_itn = True
    language = "zh"
    num_threads = 4
    provider = "cpu"
    debug = False


class FunASRNanoGGUFArgs:
    encoder_onnx_path = ModelPaths.fun_asr_nano_gguf_encoder_adaptor.as_posix()
    ctc_onnx_path = ModelPaths.fun_asr_nano_gguf_ctc.as_posix()
    decoder_gguf_path = ModelPaths.fun_asr_nano_gguf_llm_decode.as_posix()
    tokens_path = ModelPaths.fun_asr_nano_gguf_token.as_posix()
    hotwords_path = ModelPaths.fun_asr_nano_gguf_hotwords.as_posix()

    dml_enable = False
    vulkan_enable = True
    vulkan_force_fp32 = False

    enable_ctc = True
    n_predict = 512
    n_threads = None
    similar_threshold = 0.6
    max_hotwords = 20
    verbose = False
