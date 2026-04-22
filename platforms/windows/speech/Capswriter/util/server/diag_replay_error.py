# coding: utf-8
"""
Paraformer 切片诊断工具 - 复现脚本
读取保存的 .pkl 错误现场音频，重新运行识别并输出详细结果。
"""

import os
import sys
import pickle
import numpy as np

from pathlib import Path

# 模型路径配置
BASE_DIR = Path(__file__).parent.parent.parent
MODEL_DIR = BASE_DIR / 'models'
FUNASR_NANO_DIR = MODEL_DIR / 'FunASR-nano' / 'sherpa-onnx-funasr-nano-int8-2025-12-30'

class FunASRNanoArgs:
    """FunASR-nano 模型参数配置"""
    encoder_adaptor = (FUNASR_NANO_DIR / 'encoder_adaptor.int8.onnx').as_posix()
    llm_prefill = (FUNASR_NANO_DIR / 'llm_prefill.int8.onnx').as_posix()
    llm_decode = (FUNASR_NANO_DIR / 'llm_decode.int8.onnx').as_posix()
    embedding = (FUNASR_NANO_DIR / 'embedding.int8.onnx').as_posix()
    tokenizer = (FUNASR_NANO_DIR / 'Qwen3-0.6B').as_posix()
    num_threads = 4
    provider = 'cpu'
    debug = False
    system_prompt = "You are a helpful assistant."
    user_prompt = "Transcription:"
    max_new_tokens = 512
    temperature = 0.3
    top_p = 0.8
    seed = 42

def check_model():
    """检查 FunASR-nano 模型文件是否存在"""
    required_files = [
        Path(FunASRNanoArgs.tokenizer),
        Path(FunASRNanoArgs.encoder_adaptor),
        Path(FunASRNanoArgs.embedding),
        Path(FunASRNanoArgs.llm_prefill),
        Path(FunASRNanoArgs.llm_decode),
    ]
    missing = [f for f in required_files if not f.exists()]
    if missing:
        print("以下模型文件缺失，请检查 models 目录：")
        for f in missing:
            print(f"  - {f}")
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("用法: python diag_replay_error.py <pkl_file>")
        return

    pkl_file = sys.argv[1]
    if not os.path.exists(pkl_file):
        print(f"文件不存在: {pkl_file}")
        return

    print(f"正在加载错误音频: {pkl_file}")
    with open(pkl_file, 'rb') as f:
        samples = pickle.load(f)

    print(f"音频长度: {len(samples)} samples ({len(samples)/16000:.2f}s)")

    try:
        # 加载模型
        print("正在载入 FunASR-Nano 模型...")
        import sherpa_onnx
        check_model()
        recognizer = sherpa_onnx.OfflineRecognizer.from_funasr_nano(
            **{key: value for key, value in FunASRNanoArgs.__dict__.items() if not key.startswith('_')}
        )
        print("模型载入完成")

        # 运行识别
        print("\n--- 重新运行识别 ---")
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, samples)
        recognizer.decode_stream(stream)
        
        print("\n[识别文本]:")
        print(stream.result.text)
        
        print("\n[详细结果 (stream.result)]:")
        print(f"Tokens: {stream.result.tokens}")
        print(f"Timestamps: {stream.result.timestamps}")
        
    except Exception as e:
        print(f"\n复现时发生错误!")
        print(f"类型: {type(e).__name__}")
        print(f"内容: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
