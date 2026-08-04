//! AhaKey 协议层
//!
//! 负责 BLE 通信的字节序编解码、状态机解析、high-level 业务命令构造。
//! 对应 macOS `AhaKeyProtocol.swift` / Java `AhaKeyProtocol.java`。
//!
//! ## 模块组成
//! - `packet`:   命令枚举(`AhaKeyCommand`)、按键子类型(`KeySubType`)、响应结构、协议常量
//! - `codec`:    帧编解码(`ProtocolCodec::encode/decode`)
//! - `builder`:  high-level 业务命令构造器(`set_key_mapping`、`change_name` 等)
//!
//! ## 帧格式
//! ```text
//! [AA BB] [cmd:1] [payload:N] [CC DD]
//! ```
//!
//! ## 字节级一致性保证
//! 所有 `builder` 函数产生的字节**必须**与 macOS / Java 端对应函数一致,
//! 由 `cargo test` 中 `*_byte_identical_to_macos` 标记的测试强制校验。

pub mod builder;
pub mod codec;
pub mod packet;

pub use builder::{
    change_appearance, change_name, preview_light_effect, prepare_write, query_capabilities,
    query_device_status, read_pic_state, save_config, set_brightness, set_key_description,
    set_key_macro, set_key_mapping, set_light_mapping, set_work_mode, update_picture,
    update_picture_for_mode, update_state,
};
pub use codec::ProtocolCodec;
pub use packet::{
    AhaKeyCommand, AhaKeyResponse, KeySubType, OLED_CHUNK_SIZE, OLED_FACTORY_RESERVED_SLOTS,
    OLED_FRAME_BYTES, OLED_FRAME_SLOT_SIZE, OLED_HEIGHT, OLED_MAX_FRAMES_PER_MODE,
    OLED_PACKET_SIZE, OLED_WIDTH, PROTOCOL_HEADER, PROTOCOL_TRAILER,
};
