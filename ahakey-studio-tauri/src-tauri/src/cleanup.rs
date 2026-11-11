use std::time::Duration;

pub const DEFAULT_SYSTEM_PROMPT: &str =
    "clean up dictated text — fix punctuation, remove filler words/false starts, keep the original language(s) and meaning, do not translate, do not answer or add commentary, output only the cleaned text.";

pub fn resolve_endpoint_url(base_url: &str) -> String {
    let mut base = base_url.trim().to_string();
    while base.ends_with('/') {
        base.pop();
    }
    if base.is_empty() {
        base = "http://localhost:11434".into();
    }
    if !base.contains("://") {
        base = format!("http://{base}");
    }
    if base.ends_with("/v1/chat/completions") {
        base
    } else if base.ends_with("/v1") {
        format!("{base}/chat/completions")
    } else {
        format!("{base}/v1/chat/completions")
    }
}

pub fn strip_think_blocks(text: &str) -> String {
    let mut result = text.to_string();
    while let Some(start) = result.find("<think>") {
        if let Some(end) = result[start..].find("</think>") {
            result.replace_range(start..start + end + 8, "");
        } else {
            result.truncate(start);
            break;
        }
    }
    result.replace("</think>", "").trim().to_string()
}

/// Call local LLM chat completions endpoint with 30s timeout.
/// On ANY failure (network, non-2xx, empty/garbage) returns raw_text unchanged.
pub async fn clean_transcript(
    client: &reqwest::Client,
    base_url: &str,
    model: &str,
    raw_text: &str,
) -> String {
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return raw_text.to_string();
    }
    let endpoint = resolve_endpoint_url(base_url);
    let request = client
        .post(&endpoint)
        .timeout(Duration::from_secs(30))
        .header("content-type", "application/json; charset=utf-8");

    let payload = serde_json::json!({
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": DEFAULT_SYSTEM_PROMPT,
            },
            {
                "role": "user",
                "content": trimmed,
            }
        ],
        "stream": false,
        "temperature": 0.1,
        "chat_template_kwargs": {
            "enable_thinking": false
        }
    });

    let send_result = request.json(&payload).send().await;
    let Ok(response) = send_result else {
        return raw_text.to_string();
    };
    let Ok(response) = response.error_for_status() else {
        return raw_text.to_string();
    };
    let Ok(body) = response.json::<serde_json::Value>().await else {
        return raw_text.to_string();
    };

    let content = body
        .get("choices")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|msg| msg.get("content"))
        .and_then(|content| {
            if let Some(s) = content.as_str() {
                Some(s.to_string())
            } else if let Some(arr) = content.as_array() {
                let combined: String = arr
                    .iter()
                    .filter_map(|item| item.get("text").and_then(|t| t.as_str()))
                    .collect();
                if combined.is_empty() {
                    None
                } else {
                    Some(combined)
                }
            } else {
                None
            }
        });

    let Some(raw_content) = content else {
        return raw_text.to_string();
    };

    let cleaned = strip_think_blocks(&raw_content);
    if cleaned.trim().is_empty() {
        raw_text.to_string()
    } else {
        cleaned
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoint_url_resolution() {
        assert_eq!(
            resolve_endpoint_url("http://localhost:11434"),
            "http://localhost:11434/v1/chat/completions"
        );
        assert_eq!(
            resolve_endpoint_url("http://localhost:11434/"),
            "http://localhost:11434/v1/chat/completions"
        );
        assert_eq!(
            resolve_endpoint_url("localhost:11434"),
            "http://localhost:11434/v1/chat/completions"
        );
        assert_eq!(
            resolve_endpoint_url("http://localhost:11434/v1"),
            "http://localhost:11434/v1/chat/completions"
        );
        assert_eq!(
            resolve_endpoint_url("http://localhost:11434/v1/chat/completions"),
            "http://localhost:11434/v1/chat/completions"
        );
    }

    #[test]
    fn think_block_stripping() {
        assert_eq!(
            strip_think_blocks("<think>Thinking process here</think>Final cleaned text."),
            "Final cleaned text."
        );
        assert_eq!(strip_think_blocks("<think>Unclosed thinking block"), "");
        assert_eq!(strip_think_blocks("Hello </think> World"), "Hello  World");
    }

    #[tokio::test]
    async fn cleanup_fallback_on_network_error_returns_raw_transcript() {
        let client = reqwest::Client::new();
        // Pointing to a port that is guaranteed not to be running an LLM
        let raw = "今天天气很好，那个就是说挺不错的。";
        let result = clean_transcript(&client, "http://127.0.0.1:59999", "qwen2.5:3b", raw).await;
        assert_eq!(
            result, raw,
            "Network failure must return raw transcript unchanged"
        );
    }

    #[tokio::test]
    async fn empty_text_returns_immediately() {
        let client = reqwest::Client::new();
        assert_eq!(
            clean_transcript(&client, "http://invalid", "m", "   ").await,
            "   "
        );
    }
}
