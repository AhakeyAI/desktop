//! 按键配置模型 — 前后端共享

use serde::{Deserialize, Serialize};

use crate::model::voice_preset::VoicePreset;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum KeyId {
    Key1,
    Key2,
    Key3,
    Key4,
    Key5,
    Key6,
    Key7,
    Key8,
    Knob,
}

impl KeyId {
    pub fn index(&self) -> usize {
        match self {
            KeyId::Key1 => 0,
            KeyId::Key2 => 1,
            KeyId::Key3 => 2,
            KeyId::Key4 => 3,
            KeyId::Key5 => 4,
            KeyId::Key6 => 5,
            KeyId::Key7 => 6,
            KeyId::Key8 => 7,
            KeyId::Knob => 8,
        }
    }

    pub fn all() -> [KeyId; 9] {
        [KeyId::Key1, KeyId::Key2, KeyId::Key3, KeyId::Key4, KeyId::Key5,
         KeyId::Key6, KeyId::Key7, KeyId::Key8, KeyId::Knob]
    }

    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            1 => Self::Key1,
            2 => Self::Key2,
            3 => Self::Key3,
            4 => Self::Key4,
            5 => Self::Key5,
            6 => Self::Key6,
            7 => Self::Key7,
            8 => Self::Key8,
            9 => Self::Knob,
            _ => return None,
        })
    }

    pub fn label(&self) -> &'static str {
        match self {
            KeyId::Knob => "Knob",
            _ => match self.index() + 1 {
                1 => "K1",
                2 => "K2",
                3 => "K3",
                4 => "K4",
                5 => "K5",
                6 => "K6",
                7 => "K7",
                8 => "K8",
                _ => "?",
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyCodeBinding {
    pub key: String,
    pub code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyConfig {
    pub id: u8,
    pub label: String,
    pub name: String,
    pub bindings: Vec<KeyCodeBinding>,
    pub voice_preset: VoicePreset,
}

impl KeyConfig {
    pub fn new(id: u8, label: &str, name: &str) -> Self {
        Self {
            id,
            label: label.to_string(),
            name: name.to_string(),
            bindings: Vec::new(),
            voice_preset: VoicePreset::WindowsNative,
        }
    }

    pub fn with_bindings(mut self, bindings: Vec<KeyCodeBinding>) -> Self {
        self.bindings = bindings;
        self
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ModeSlot {
    pub mode: u8,
    pub name: String,
}

