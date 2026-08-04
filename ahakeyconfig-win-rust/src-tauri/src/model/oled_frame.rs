//! OLED 帧模型与编码器
//!
//! 对应原 `OLEDFrameEncoder.java`,将 128x32 单色位图编码为设备协议帧。

use serde::{Deserialize, Serialize};

pub const OLED_WIDTH: usize = 128;
pub const OLED_HEIGHT: usize = 32;
pub const OLED_BYTES: usize = (OLED_WIDTH * OLED_HEIGHT) / 8;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OledFrame {
    pub width: u8,
    pub height: u8,
    /// 单色位图,按行扫描,LSB 优先
    pub data: Vec<u8>,
}

impl OledFrame {
    pub fn blank() -> Self {
        Self {
            width: OLED_WIDTH as u8,
            height: OLED_HEIGHT as u8,
            data: vec![0u8; OLED_BYTES],
        }
    }

    pub fn from_pixels(pixels: &[u8]) -> Self {
        assert_eq!(pixels.len(), OLED_WIDTH * OLED_HEIGHT);
        let mut data = vec![0u8; OLED_BYTES];
        for y in 0..OLED_HEIGHT {
            for x in 0..OLED_WIDTH {
                if pixels[y * OLED_WIDTH + x] != 0 {
                    let byte = (y * OLED_WIDTH + x) / 8;
                    let bit = (y * OLED_WIDTH + x) % 8;
                    data[byte] |= 1 << bit;
                }
            }
        }
        Self {
            width: OLED_WIDTH as u8,
            height: OLED_HEIGHT as u8,
            data,
        }
    }
}

/// OLED 帧编码器
pub struct OledFrameEncoder;

impl OledFrameEncoder {
    /// 编码为协议负载
    pub fn encode(frame: &OledFrame) -> Vec<u8> {
        let mut out = Vec::with_capacity(2 + frame.data.len());
        out.push(frame.width);
        out.push(frame.height);
        out.extend_from_slice(&frame.data);
        out
    }

    /// RLE 压缩
    pub fn encode_rle(frame: &OledFrame) -> Vec<u8> {
        let mut out = Vec::with_capacity(2 + frame.data.len());
        out.push(frame.width);
        out.push(frame.height);
        let mut i = 0;
        while i < frame.data.len() {
            let cur = frame.data[i];
            let mut run = 1usize;
            while i + run < frame.data.len() && frame.data[i + run] == cur && run < 127 {
                run += 1;
            }
            if run >= 3 {
                out.push(0x80 | run as u8);
                out.push(cur);
                i += run;
            } else {
                out.push(cur);
                i += 1;
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blank() {
        let f = OledFrame::blank();
        assert_eq!(f.data.len(), OLED_BYTES);
    }

    #[test]
    fn test_encode() {
        let f = OledFrame::blank();
        let encoded = OledFrameEncoder::encode(&f);
        assert_eq!(encoded.len(), 2 + OLED_BYTES);
    }
}

