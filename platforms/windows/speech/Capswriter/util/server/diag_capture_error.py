# coding: utf-8
"""
Paraformer 切片诊断工具 - 捕获脚本
模拟服务端 25s 切片识别流程，捕获并保存导致错误的现场音频。
"""

import os
import sys
import subprocess
import numpy as np
import pickle
import time
from pathlib import Path
from datetime import datetime

# 模型路径配置
BASE_DIR = Path().parent.parent.parent
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

def convert_audio(input_file: str, output_wav: str):
    """使用 ffmpeg 将输入文件转换为 16kHz, mono, float32 WAV"""
    print(f"正在转换音频: {input_file} -> {output_wav}")
    cmd = [
        'ffmpeg', '-y',
        '-i', input_file,
        '-ar', '16000',
        '-ac', '1',
        '-f', 'f32le', # 直接输出 float32 原始数据，后续 numpy 读取更方便
        output_wav
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        print("音频转换成功")
    except subprocess.CalledProcessError as e:
        print(f"音频转换失败: {e.stderr.decode()}")
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("用法: python diag_capture_error.py <media_file> [segment_duration=25]")
        return

    input_file = sys.argv[1]
    seg_duration = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    
    # 临时文件
    temp_raw = "temp_diag.raw"
    convert_audio(input_file, temp_raw)

    try:
        # 加载模型
        print("正在载入 FunASR-Nano 模型...")
        import sherpa_onnx
        check_model()
        recognizer = sherpa_onnx.OfflineRecognizer.from_funasr_nano(
            **{key: value for key, value in FunASRNanoArgs.__dict__.items() if not key.startswith('_')}
        )
        print("模型载入完成")

        # 读取音频数据
        samples = np.fromfile(temp_raw, dtype=np.float32)
        total_samples = len(samples)
        sample_rate = 16000
        seg_samples = seg_duration * sample_rate
        
        print(f"总时长: {total_samples / sample_rate:.2f}s")
        print(f"开始模拟切片识别 (切片长度: {seg_duration}s)...")

        for start in range(0, total_samples, seg_samples):
            end = min(start + seg_samples, total_samples)
            chunk = samples[start:end]
            
            # 记录识别现场
            try:
                stream = recognizer.create_stream()
                stream.accept_waveform(sample_rate, chunk)
                recognizer.decode_stream(stream)
                print(f"[{start/sample_rate:.1f}s - {end/sample_rate:.1f}s]: {stream.result.tokens}")
                
                # 这里可以加一些特定的错误判定，比如返回结果为空但音频有声等
                # 或者捕获在 server_recognize.py 中提到的 UnicodeDecodeError
            except Exception as e:
                print(f"\n捕获到识别错误! 在片段: {start/sample_rate:.1f}s - {end/sample_rate:.1f}s")
                print(f"错误类型: {type(e).__name__}, 内容: {e}")
                
                
                # 保存现场
                log_dir = Path("logs")
                log_dir.mkdir(exist_ok=True)
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = log_dir / f"diag_error_audio_{timestamp}_{start//sample_rate}s.pkl"
                
                with open(filename, 'wb') as f:
                    pickle.dump(chunk, f)
                
                print(f"错误现场音频已保存到: {filename}")
                # 产生错误后是否继续？通常我们想停下来分析。
                # sys.exit(0) 

    finally:
        if os.path.exists(temp_raw):
            os.remove(temp_raw)

if __name__ == "__main__":
    main()
