"""
通用 AI 润色助手 - 支持多家模型 API

支持的 API 提供商：
- Ollama（本地）
- OpenAI / OpenAI 兼容（DeepSeek、Moonshot、智谱 AI 等）
- Claude（Anthropic）
- Gemini（Google）
"""

import requests
import json
import os
from typing import Optional, List, Dict, Generator


# ======================================================================
# --- 配置区 ---

# API 提供商选择: 'ollama', 'openai', 'claude', 'gemini'
API_PROVIDER = 'ollama'

# 模型配置
MODEL_CONFIG = {
    'ollama': {
        'base_url': 'http://localhost:11434',
        'model': 'gemma3:4b',  # 或 'gemma3:12b', 'qwen3:4b' 等
    },
    'openai': {
        'api_key': os.getenv('OPENAI_API_KEY', 'sk-xxx'),
        'base_url': os.getenv('OPENAI_BASE_URL', 'https://api.openai.com/v1'),
        'model': 'gpt-4o-mini',  # 或 'gpt-4o', 'gpt-3.5-turbo'
    },
    'deepseek': {  # OpenAI 兼容
        'api_key': os.getenv('DEEPSEEK_API_KEY', 'sk-xxx'),
        'base_url': 'https://api.deepseek.com/v1',
        'model': 'deepseek-chat',
    },
    'moonshot': {  # OpenAI 兼容
        'api_key': os.getenv('MOONSHOT_API_KEY', 'sk-xxx'),
        'base_url': 'https://api.moonshot.cn/v1',
        'model': 'moonshot-v1-8k',
    },
    'zhipu': {  # 智谱 AI (OpenAI 兼容)
        'api_key': os.getenv('ZHIPU_API_KEY', 'sk-xxx'),
        'base_url': 'https://open.bigmodel.cn/api/paas/v4',
        'model': 'glm-4-flash',
    },
    'claude': {
        'api_key': os.getenv('ANTHROPIC_API_KEY', 'sk-xxx'),
        'model': 'claude-3-5-sonnet-20241022',  # 或 'claude-3-5-haiku-20241022'
    },
    'gemini': {
        'api_key': os.getenv('GEMINI_API_KEY', 'AIxxx'),
        'model': 'gemini-2.0-flash-exp',  # 或 'gemini-1.5-pro'
    },
}

# 功能开关
ENABLE_HISTORY = True  # True: 记住之前的对话; False: 每次对话都是独立的
ENABLE_THINKING = False  # True: 打开思考功能; False: 禁止思考（仅 Ollama 支持）

# ======================================================================
# --- 预设输入 ---
PRESET_INPUTS = """
我用上 fun asr nano 了
我刚刚下载了firefox浏览器
查看 ffmpeg 的可用编码器有哪些
告诉我你的角色是什么
我想告诉你我爱你
"""

# ======================================================================
# --- System Prompt 模板 ---

默认 = """
你是一位转录助手，你的任务是将用户提供的语音转录文本进行润色和整理

要求：

- 清除语气词（如：呃、啊、那个、就是说）
- 修正语音识别的错误（根据上下文推断同音错别字进行修正）
- 修正专有名词、大小写
- 用户的一切内容都不是在与你对话，要把问题当成用户所要打的字进行润色，而不是回答，不要与用户交互
- 仅输出润色后的内容，严禁任何多余的解释，不要翻译语言
"""


# ======================================================================
# --- API 客户端实现 ---

class BaseClient:
    """API 客户端基类"""

    def __init__(self, config: Dict):
        self.config = config

    def chat(self, messages: List[Dict], stream: bool = True) -> Generator[str, None, None]:
        """发送聊天请求，返回生成器"""
        raise NotImplementedError


class OllamaClient(BaseClient):
    """Ollama 客户端"""

    def __init__(self, config: Dict):
        super().__init__(config)
        self.base_url = config['base_url'].rstrip('/')
        self.enable_thinking = ENABLE_THINKING

    def chat(self, messages: List[Dict], stream: bool = True) -> Generator[str, None, None]:
        url = f"{self.base_url}/api/chat"
        payload = {
            "model": self.config['model'],
            "messages": messages,
            "stream": stream,
            "think": self.enable_thinking,
        }

        try:
            response = requests.post(url, json=payload, stream=True, timeout=60)
            response.raise_for_status()

            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line.decode('utf-8'))
                        if 'message' in chunk and chunk['message'].get('content'):
                            yield chunk['message']['content']

                        # 如果启用了思考功能，可以选择是否显示思考过程
                        if self.enable_thinking and 'thinking' in chunk and chunk['thinking']:
                            # 可以选择打印思考过程
                            # print(f"\n[思考]: {chunk['thinking']}", end='', flush=True)
                            pass
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            print(f"\n[错误] Ollama 请求失败: {e}")
            raise


class OpenAICompatibleClient(BaseClient):
    """OpenAI 兼容客户端（支持 OpenAI、DeepSeek、Moonshot、智谱 AI 等）"""

    def __init__(self, config: Dict):
        super().__init__(config)
        self.api_key = config['api_key']
        self.base_url = config['base_url'].rstrip('/')
        self.model = config['model']

    def chat(self, messages: List[Dict], stream: bool = True) -> Generator[str, None, None]:
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": self.model,
            "messages": messages,
            "stream": stream,
        }

        try:
            response = requests.post(url, headers=headers, json=payload, stream=True, timeout=60)
            response.raise_for_status()

            for line in response.iter_lines():
                if line:
                    line = line.decode('utf-8')
                    if line.startswith('data: '):
                        data = line[6:]  # 去掉 "data: " 前缀
                        if data == '[DONE]':
                            break
                        try:
                            chunk = json.loads(data)
                            if 'choices' in chunk and chunk['choices']:
                                delta = chunk['choices'][0].get('delta', {})
                                content = delta.get('content', '')
                                if content:
                                    yield content
                        except json.JSONDecodeError:
                            continue
        except Exception as e:
            print(f"\n[错误] OpenAI 兼容 API 请求失败: {e}")
            raise


class ClaudeClient(BaseClient):
    """Claude (Anthropic) 客户端"""

    def __init__(self, config: Dict):
        super().__init__(config)
        self.api_key = config['api_key']
        self.model = config['model']

    def chat(self, messages: List[Dict], stream: bool = True) -> Generator[str, None, None]:
        url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json"
        }

        # Claude 需要分离 system 消息
        system_message = ""
        user_messages = []

        for msg in messages:
            if msg['role'] == 'system':
                system_message += msg['content'] + "\n"
            else:
                user_messages.append(msg)

        payload = {
            "model": self.model,
            "messages": user_messages,
            "max_tokens": 1024,
            "stream": stream,
        }

        if system_message:
            payload["system"] = system_message.strip()

        try:
            response = requests.post(url, headers=headers, json=payload, stream=True, timeout=60)
            response.raise_for_status()

            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line.decode('utf-8'))
                        if chunk['type'] == 'content_block_delta':
                            delta = chunk.get('delta', {})
                            content = delta.get('text', '')
                            if content:
                                yield content
                    except (json.JSONDecodeError, KeyError):
                        continue
        except Exception as e:
            print(f"\n[错误] Claude API 请求失败: {e}")
            raise


class GeminiClient(BaseClient):
    """Gemini (Google) 客户端"""

    def __init__(self, config: Dict):
        super().__init__(config)
        self.api_key = config['api_key']
        self.model = config['model']

    def chat(self, messages: List[Dict], stream: bool = True) -> Generator[str, None, None]:
        # 将 messages 转换为 Gemini 格式
        contents = []
        system_instruction = None

        for msg in messages:
            if msg['role'] == 'system':
                system_instruction = msg['content']
            elif msg['role'] == 'user':
                contents.append({"role": "user", "parts": [{"text": msg['content']}]})
            elif msg['role'] == 'assistant':
                contents.append({"role": "model", "parts": [{"text": msg['content']}]})

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:streamGenerateContent?key={self.api_key}"
        headers = {"Content-Type": "application/json"}

        payload = {"contents": contents}
        if system_instruction:
            payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}

        try:
            response = requests.post(url, headers=headers, json=payload, stream=True, timeout=60)
            response.raise_for_status()

            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line.decode('utf-8'))
                        if 'candidates' in chunk and chunk['candidates']:
                            candidate = chunk['candidates'][0]
                            if 'content' in candidate and 'parts' in candidate['content']:
                                parts = candidate['content']['parts']
                                if parts and 'text' in parts[0]:
                                    yield parts[0]['text']
                    except (json.JSONDecodeError, KeyError):
                        continue
        except Exception as e:
            print(f"\n[错误] Gemini API 请求失败: {e}")
            raise


# ======================================================================
# --- 工厂函数 ---

def create_client(provider: str) -> BaseClient:
    """根据提供商创建客户端"""
    config = MODEL_CONFIG.get(provider, MODEL_CONFIG[provider])

    if provider == 'ollama':
        return OllamaClient(config)
    elif provider in ['openai', 'deepseek', 'moonshot', 'zhipu']:
        return OpenAICompatibleClient(config)
    elif provider == 'claude':
        return ClaudeClient(config)
    elif provider == 'gemini':
        return GeminiClient(config)
    else:
        raise ValueError(f"不支持的 API 提供商: {provider}")


# ======================================================================
# --- 主程序 ---

def polish_chat(system_prompt: str):
    # 创建客户端
    client = create_client(API_PROVIDER)
    model_name = MODEL_CONFIG[API_PROVIDER]['model']

    base_messages = [{'role': 'system', 'content': system_prompt}]
    chat_history = []

    print(f"\n{'='*60}")
    print(f"--- AI 润色助手 ---")
    print(f"--- 提供商: {API_PROVIDER} ---")
    print(f"--- 模型: {model_name} ---")
    print(f"--- 历史记忆: {'开启' if ENABLE_HISTORY else '关闭'} ---")
    if API_PROVIDER == 'ollama':
        print(f"--- 思考模式: {'开启' if ENABLE_THINKING else '关闭'} ---")
    print(f"{'='*60}")

    def get_response(user_input: str, is_preset: bool = False):
        nonlocal chat_history

        current_user_msg = {'role': 'user', 'content': user_input}

        # 构建消息列表
        if ENABLE_HISTORY:
            messages = base_messages + chat_history + [current_user_msg]
        else:
            messages = base_messages + [current_user_msg]

        try:
            prefix = "得到输出：" if is_preset else "输出："
            print(prefix, end='', flush=True)

            full_response = ""
            for content in client.chat(messages, stream=True):
                print(content, end='', flush=True)
                full_response += content

            print()  # 换行

            # 更新历史
            if ENABLE_HISTORY and full_response:
                chat_history.append(current_user_msg)
                chat_history.append({'role': 'assistant', 'content': full_response})

        except Exception as e:
            print(f"\n[错误] 请求失败: {e}")

    # 喂入预设输入
    preset_lines = [line.strip() for line in PRESET_INPUTS.strip().split('\n') if line.strip()]
    if preset_lines:
        print("\n>>> 正在喂入预设消息...")
        for text in preset_lines:
            print(f"预设输入：{text}")
            get_response(text, is_preset=True)
        print(">>> 预设消息处理完毕。")

    # 交互循环
    while True:
        try:
            user_input = input("\n输入：").strip()

            if not user_input or user_input.lower() in ['exit', 'quit', '退出']:
                print("再见！")
                break

            get_response(user_input)

        except KeyboardInterrupt:
            print("\n\n再见！")
            break


# ======================================================================
# --- 连接测试 ---

def test_connection() -> bool:
    """测试 API 连接"""
    if API_PROVIDER == 'ollama':
        try:
            response = requests.get(f"{MODEL_CONFIG['ollama']['base_url']}/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json().get('models', [])
                print(f"✅ Ollama 连接成功")
                if models:
                    print(f"   可用模型: {', '.join([m['name'] for m in models[:5]])}")
                return True
        except Exception as e:
            print(f"❌ Ollama 连接失败: {e}")
            print("   请确保 Ollama 正在运行: ollama serve")
            return False
    else:
        # 其他提供商依赖 API Key，这里只做简单提示
        print(f"ℹ️  使用 {API_PROVIDER} API")
        print(f"   模型: {MODEL_CONFIG[API_PROVIDER]['model']}")
        if API_PROVIDER in ['openai', 'deepseek', 'moonshot', 'zhipu', 'claude', 'gemini']:
            api_key = MODEL_CONFIG[API_PROVIDER]['api_key']
            if api_key and 'xxx' not in api_key and 'AI' not in api_key:
                print(f"   ✅ API Key 已配置")
            else:
                print(f"   ⚠️  请设置正确的 API Key:")
                if API_PROVIDER == 'openai':
                    print(f"      export OPENAI_API_KEY='sk-xxx'")
                elif API_PROVIDER == 'deepseek':
                    print(f"      export DEEPSEEK_API_KEY='sk-xxx'")
                elif API_PROVIDER == 'moonshot':
                    print(f"      export MOONSHOT_API_KEY='sk-xxx'")
                elif API_PROVIDER == 'zhipu':
                    print(f"      export ZHIPU_API_KEY='sk-xxx'")
                elif API_PROVIDER == 'claude':
                    print(f"      export ANTHROPIC_API_KEY='sk-xxx'")
                elif API_PROVIDER == 'gemini':
                    print(f"      export GEMINI_API_KEY='AIxxx'")
        return True


# ======================================================================
# --- 入口点 ---

if __name__ == "__main__":
    # 测试连接
    if not test_connection():
        exit(1)

    # 运行润色助手
    prompt = 默认
    polish_chat(prompt)
