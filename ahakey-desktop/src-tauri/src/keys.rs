use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Binding {
    pub action: Action,
    pub shortcut: String,
    pub label: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "kebab-case")]
pub enum Action {
    Voice,
    Shortcut,
    Disabled,
}
pub fn defaults(accept: &str, reject: &str) -> Vec<Binding> {
    [
        (Action::Voice, "", "Voice"),
        (Action::Shortcut, accept, "Accept"),
        (Action::Shortcut, reject, "Cancel"),
        (Action::Shortcut, "Backspace", "Backspace"),
    ]
    .into_iter()
    .map(|(action, shortcut, label)| Binding {
        action,
        shortcut: shortcut.into(),
        label: label.into(),
    })
    .collect()
}
impl Binding {
    pub fn hid(&self, mode: usize) -> Result<Vec<u8>, String> {
        if self.label.len() > 80 || self.label.chars().any(char::is_control) {
            return Err("按键名称过长或包含控制字符".into());
        }
        match self.action {
            Action::Voice => Ok(vec![if mode == 1 { 0x6c } else { 0x6d }]),
            Action::Disabled => Ok(vec![]),
            Action::Shortcut => parse_shortcut(&self.shortcut),
        }
    }
}
pub fn parse_shortcut(value: &str) -> Result<Vec<u8>, String> {
    if value.len() > 80 {
        return Err("快捷键过长".into());
    }
    let parts: Vec<_> = value.split('+').map(str::trim).collect();
    let mut codes = vec![];
    for (index, part) in parts.iter().enumerate() {
        let text = part.to_ascii_uppercase();
        let modifier = match text.as_str() {
            "CTRL" | "CONTROL" => Some(0xe0),
            "SHIFT" => Some(0xe1),
            "ALT" => Some(0xe2),
            "WIN" | "META" | "SUPER" => Some(0xe3),
            _ => None,
        };
        let code =
            if index + 1 < parts.len() {
                modifier.ok_or("组合键格式为 Ctrl+Shift+V，修饰键放前面")?
            } else {
                if modifier.is_some() {
                    return Err("修饰键后需要一个按键，例如 Ctrl+Enter".into());
                }
                match text.as_str() {
                    "ENTER" => 0x28,
                    "ESC" | "ESCAPE" => 0x29,
                    "BACKSPACE" => 0x2a,
                    "TAB" => 0x2b,
                    "SPACE" => 0x2c,
                    "DELETE" => 0x4c,
                    "INSERT" => 0x49,
                    "HOME" => 0x4a,
                    "END" => 0x4d,
                    "PAGEUP" => 0x4b,
                    "PAGEDOWN" => 0x4e,
                    "RIGHT" | "ARROWRIGHT" => 0x4f,
                    "LEFT" | "ARROWLEFT" => 0x50,
                    "DOWN" | "ARROWDOWN" => 0x51,
                    "UP" | "ARROWUP" => 0x52,
                    "MINUS" => 0x2d,
                    "EQUAL" => 0x2e,
                    "COMMA" => 0x36,
                    "PERIOD" => 0x37,
                    "SLASH" => 0x38,
                    _ if text.len() == 1 && text.as_bytes()[0].is_ascii_uppercase() => {
                        0x04 + text.as_bytes()[0] - b'A'
                    }
                    _ if text.len() == 1 && text.as_bytes()[0].is_ascii_digit() => {
                        if text == "0" {
                            0x27
                        } else {
                            0x1e + text.as_bytes()[0] - b'1'
                        }
                    }
                    _ => match text
                        .strip_prefix('F')
                        .and_then(|n| n.parse::<u8>().ok())
                        .filter(|n| (1..=12).contains(n))
                    {
                        Some(n) => 0x3a + n - 1,
                        None => return Err(
                            "不支持此快捷键。可用字母、数字、F1–F12、Enter 等；F17/F18 保留给语音"
                                .into(),
                        ),
                    },
                }
            };
        if codes.contains(&code) {
            return Err("快捷键包含重复按键".into());
        }
        codes.push(code);
    }
    Ok(codes)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn encodes_four_independent_bindings_and_modifiers() {
        let keys = defaults("Ctrl+Enter", "Escape");
        assert_eq!(keys[0].hid(0).unwrap(), vec![0x6d]);
        assert_eq!(keys[0].hid(1).unwrap(), vec![0x6c]);
        assert_eq!(keys[1].hid(0).unwrap(), vec![0xe0, 0x28]);
        assert_eq!(keys[3].hid(0).unwrap(), vec![0x2a]);
        assert_eq!(
            parse_shortcut("Ctrl+Shift+V").unwrap(),
            vec![0xe0, 0xe1, 0x19]
        );
        assert_eq!(parse_shortcut("F12").unwrap(), vec![0x45]);
    }
    #[test]
    fn rejects_incomplete_ambiguous_and_reserved_shortcuts() {
        for text in [
            "",
            "Ctrl",
            "Ctrl+",
            "Ctrl+Ctrl+A",
            "A+B",
            "F17",
            "F18",
            "F99",
            "run something",
        ] {
            assert!(parse_shortcut(text).is_err(), "{text}");
        }
    }
    #[test]
    fn disabled_key_sends_no_usage() {
        assert!(Binding {
            action: Action::Disabled,
            shortcut: "".into(),
            label: "Off".into()
        }
        .hid(0)
        .unwrap()
        .is_empty());
    }
}
