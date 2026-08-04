//! OLED 上传服务

use crate::error::AppResult;
use crate::model::OledFrame;

/// OLED 上传服务
pub struct OledUploadService;

impl OledUploadService {
    pub fn new() -> Self {
        Self
    }

    /// 编码帧为协议负载
    pub fn encode(&self, frame: &OledFrame) -> AppResult<Vec<u8>> {
        Ok(crate::model::OledFrameEncoder::encode(frame))
    }

    /// 编码帧(使用 RLE 压缩)
    pub fn encode_rle(&self, frame: &OledFrame) -> AppResult<Vec<u8>> {
        Ok(crate::model::OledFrameEncoder::encode_rle(frame))
    }
}

impl Default for OledUploadService {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode() {
        let s = OledUploadService::new();
        let frame = OledFrame::blank();
        let encoded = s.encode(&frame).unwrap();
        assert_eq!(encoded.len(), 2 + 512);
    }
}

