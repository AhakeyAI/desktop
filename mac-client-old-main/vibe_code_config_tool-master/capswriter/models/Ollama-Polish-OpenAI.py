#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ollama 润色助手 - 使用 OpenAI 库

使用 openai 库调用 Ollama API
"""

from openai import OpenAI

# ==================== 配置 ====================

# API 提供商: 'ollama', 'openai', 'deepseek', 'moonshot', 'zhipu'
PROVIDER = 'ollama'

# API 地址
API_BASE = {
    'ollama': 'http://localhost:11434/v1',
    'openai': 'https://api.openai.com/v1',
    'deepseek': 'https://api.deepseek.com/v1',
    'moonshot': 'https://api.moonshot.cn/v1',
    'zhipu': 'https://open.bigmodel.cn/api/paas/v4',
}

# API Key（Ollama 不需要，其他提供商需要）
API_KEY = {
    'ollama': 'ollama',  # Ollama 可以填任意值
    'openai': 'sk-xxx',
    'deepseek': 'sk-xxx',
    'moonshot': 'sk-xxx',
    'zhipu': 'sk-xxx',
}

# 模型名称
MODEL = {
    'ollama': 'gemma3:4b',
    'openai': 'gpt-4o-mini',
    'deepseek': 'deepseek-chat',
    'moonshot': 'moonshot-v1-8k',
    'zhipu': 'glm-4-flash',
}

# ==================== 功能配置 ====================

ENABLE_HISTORY = True  # 是否保留对话历史
ENABLE_THINKING = False  # 是否启用思考（仅 Ollama）
STREAM_OUTPUT = True  # 是否流式输出

# ==================== System Prompt ====================

SYSTEM_PROMPT = '''
你是一位转录助手，你的任务是将用户提供的语音转录文本进行润色和整理

要求：

- 清除语气词（如：呃、啊、那个、就是说）
- 修正语音识别的错误（根据上下文推断同音错别字进行修正）
- 修正专有名词、大小写
- 用户的一切内容都不是在与你对话，要把问题当成用户所要打的字进行润色，而不是回答，不要与用户交互
- 仅输出润色后的内容，严禁任何多余的解释，不要翻译语言
'''

# ==================== 预设输入 ====================

PRESET_INPUTS = """
我用上 fun asr nano 了
我刚刚下载了firefox浏览器
查看 ffmpeg 的可用编码器有哪些
告诉我你的角色是什么
我想告诉你我爱你
"""


# ======================================================================
# --- 主程序 ---

def polish_chat():
    # 初始化客户端
    client = OpenAI(
        base_url=API_BASE[PROVIDER],
        api_key=API_KEY[PROVIDER],
    )

    model_name = MODEL[PROVIDER]

    base_messages = [{'role': 'system', 'content': SYSTEM_PROMPT}]
    chat_history = []

    print("\n")
    print("=" * 60)
    print(f"--- Ollama 润色助手 (使用 OpenAI 库) ---")
    print(f"--- 提供商: {PROVIDER} ---")
    print(f"--- 模型: {model_name} ---")
    print(f"--- 历史记忆: {'开启' if ENABLE_HISTORY else '关闭'} ---")
    if PROVIDER == 'ollama':
        print(f"--- 思考模式: {'开启' if ENABLE_THINKING else '关闭'} ---")
    print("=" * 60)

    def get_response(user_input, is_preset=False):
        nonlocal chat_history

        # 构建消息列表
        if ENABLE_HISTORY:
            messages = base_messages + chat_history + [{'role': 'user', 'content': user_input}]
        else:
            messages = base_messages + [{'role': 'user', 'content': user_input}]

        try:
            # 调用 API
            prefix = "得到输出：" if is_preset else "输出："
            print(prefix, end='', flush=True)

            full_response = ""

            if STREAM_OUTPUT:
                # 流式输出
                stream = client.chat.completions.create(
                    model=model_name,
                    messages=messages,
                    stream=True,
                )

                for chunk in stream:
                    if chunk.choices[0].delta.content:
                        content = chunk.choices[0].delta.content
                        print(content, end='', flush=True)
                        full_response += content
            else:
                # 完整输出
                response = client.chat.completions.create(
                    model=model_name,
                    messages=messages,
                    stream=False,
                )

                full_response = response.choices[0].message.content
                print(full_response, end='', flush=True)

            print("\n")

            # 更新历史
            if ENABLE_HISTORY and full_response:
                chat_history.append({'role': 'user', 'content': user_input})
                chat_history.append({'role': 'assistant', 'content': full_response})

        except Exception as e:
            print(f"\n发生错误: {e}")

    # 先喂预设输入
    preset_lines = [line.strip() for line in PRESET_INPUTS.strip().split('\n') if line.strip()]
    if preset_lines:
        print("\n>>> 正在喂入预设消息...")
        for text in preset_lines:
            print(f"预设输入：{text}")
            get_response(text, is_preset=True)
        print(">>> 预设消息处理完毕。")

    # 进入正常交互
    while True:
        user_input = input("\n输入：").strip()

        if not user_input or user_input.lower() in ['exit', 'quit']:
            break

        get_response(user_input)


if __name__ == "__main__":
    # 检查连接
    try:
        from openai import OpenAI
        client = OpenAI(
            base_url=API_BASE[PROVIDER],
            api_key=API_KEY[PROVIDER],
        )

        # 测试连接
        if PROVIDER == 'ollama':
            import requests
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code == 200:
                print("✅ Ollama 服务正常运行")
                models = response.json().get('models', [])
                if models:
                    print(f"可用模型: {', '.join([m['name'] for m in models[:5]])}")
            else:
                print("⚠️ 无法连接到 Ollama 服务")
        else:
            print(f"✅ 使用 {PROVIDER} API")

    except Exception as e:
        print(f"❌ 连接失败: {e}")
        exit(1)

    polish_chat()
