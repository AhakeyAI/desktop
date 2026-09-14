//! Volcengine v3 ASR framing: <https://www.volcengine.com/docs/6561/1354869>.
use crate::CloudError;
use flate2::{read::GzDecoder, write::GzEncoder, Compression};
use serde_json::{json, Value};
use std::io::{Read, Write};
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Debug, PartialEq, Eq)]
pub struct ResultText {
    pub text: String,
    pub is_final: bool,
}

pub fn configuration() -> Result<Vec<u8>, CloudError> {
    let request = json!({"user":{"uid":"ahakey-studio"},
        "audio":{"format":"pcm","codec":"raw","rate":16000,"bits":16,"channel":1},
        "request":{"model_name":"bigmodel","enable_itn":true,"enable_punc":true,
            "result_type":"full","show_utterances":true,"enable_nonstream":true}});
    frame(
        1,
        0,
        1,
        &serde_json::to_vec(&request).map_err(|_| CloudError::Protocol)?,
    )
}
pub fn audio(pcm: &[i16], last: bool) -> Result<Vec<u8>, CloudError> {
    if pcm.len() > 3200 || (pcm.is_empty() && !last) {
        return Err(CloudError::InvalidAudio);
    }
    let bytes: Vec<u8> = pcm.iter().flat_map(|v| v.to_le_bytes()).collect();
    frame(2, if last { 2 } else { 0 }, 0, &bytes)
}
fn frame(kind: u8, flags: u8, serialization: u8, payload: &[u8]) -> Result<Vec<u8>, CloudError> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(payload)
        .map_err(|_| CloudError::Protocol)?;
    let compressed = encoder.finish().map_err(|_| CloudError::Protocol)?;
    let mut result = vec![0x11, (kind << 4) | flags, (serialization << 4) | 1, 0];
    result.extend_from_slice(&(compressed.len() as u32).to_be_bytes());
    result.extend_from_slice(&compressed);
    Ok(result)
}
pub fn parse(bytes: &[u8]) -> Result<ResultText, CloudError> {
    if bytes.len() > MAX_FRAME_BYTES {
        return Err(CloudError::TooLarge);
    }
    if bytes.len() < 8 {
        return Err(CloudError::Protocol);
    }
    let header = (bytes[0] & 15) as usize * 4;
    if bytes[0] >> 4 != 1 || header < 4 || header > bytes.len() - 4 {
        return Err(CloudError::Protocol);
    }
    let kind = bytes[1] >> 4;
    let flags = bytes[1] & 15;
    let mut cursor = header;
    if flags > 3 {
        return Err(CloudError::Protocol);
    }
    let code = if kind == 15 {
        Some(read_u32(bytes, &mut cursor)?)
    } else {
        None
    };
    let sequence = if kind != 15 && flags & 1 != 0 {
        Some(read_u32(bytes, &mut cursor)? as i32)
    } else {
        None
    };
    let length = read_u32(bytes, &mut cursor)? as usize;
    if length != bytes.len() - cursor {
        return Err(CloudError::Protocol);
    }
    let payload = match bytes[2] & 15 {
        0 => bytes[cursor..].to_vec(),
        1 => {
            let mut out = Vec::new();
            GzDecoder::new(&bytes[cursor..])
                .take(MAX_FRAME_BYTES as u64 + 1)
                .read_to_end(&mut out)
                .map_err(|_| CloudError::Protocol)?;
            if out.len() > MAX_FRAME_BYTES {
                return Err(CloudError::TooLarge);
            }
            out
        }
        _ => return Err(CloudError::Protocol),
    };
    // Validate even error frames, but never surface an arbitrary server error body.
    if let Some(code) = code {
        return Err(CloudError::Service(code));
    }
    if kind != 9 || bytes[2] >> 4 != 1 {
        return Err(CloudError::Protocol);
    }
    let json: Value = serde_json::from_slice(&payload).map_err(|_| CloudError::Protocol)?;
    if !json.is_object() {
        return Err(CloudError::Protocol);
    }
    if let Some(code) = json.get("code") {
        let code = code
            .as_u64()
            .filter(|v| *v <= u32::MAX as u64)
            .ok_or(CloudError::Protocol)? as u32;
        if code != 0 && code != 20_000_000 {
            return Err(CloudError::Service(code));
        }
    }
    let text = match &json["result"] {
        Value::Array(results) => results.iter().filter_map(|v| v["text"].as_str()).collect(),
        result => result["text"].as_str().unwrap_or("").to_owned(),
    };
    Ok(ResultText {
        text,
        is_final: flags & 2 != 0 || sequence.is_some_and(|seq| seq < 0),
    })
}
fn read_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, CloudError> {
    let chunk = bytes
        .get(*cursor..*cursor + 4)
        .ok_or(CloudError::Protocol)?;
    *cursor += 4;
    Ok(u32::from_be_bytes(
        chunk.try_into().map_err(|_| CloudError::Protocol)?,
    ))
}
#[cfg(test)]
pub(crate) fn response(text: &str, flags: u8, sequence: i32) -> Vec<u8> {
    let mut f = frame(
        9,
        flags,
        1,
        &serde_json::to_vec(&json!({"result":{"text":text}})).unwrap(),
    )
    .unwrap();
    if flags & 1 != 0 {
        f.splice(4..4, sequence.to_be_bytes());
    }
    f
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn final_negative_sequence_and_array() {
        assert_eq!(
            parse(&response("hello", 3, -2)).unwrap(),
            ResultText {
                text: "hello".into(),
                is_final: true
            }
        );
        assert!(parse(&response("negative", 1, -1)).unwrap().is_final);
        assert!(!parse(&response("partial", 1, 1)).unwrap().is_final);
        let f = frame(9, 0, 1, br#"{"result":[{"text":"a"},{"text":"b"}]}"#).unwrap();
        assert_eq!(parse(&f).unwrap().text, "ab");
    }
    #[test]
    fn rejects_lengths_versions_and_gzip_bombs() {
        let mut good = response("ok", 0, 0);
        for len in 0..8 {
            assert!(parse(&good[..len]).is_err());
        }
        good[0] = 0x21;
        assert_eq!(parse(&good), Err(CloudError::Protocol));
        good[0] = 0x11;
        good.push(0);
        assert_eq!(parse(&good), Err(CloudError::Protocol));
        let bomb = frame(9, 0, 1, &vec![b' '; MAX_FRAME_BYTES + 1]).unwrap();
        assert_eq!(parse(&bomb), Err(CloudError::TooLarge));
    }
    #[test]
    fn error_body_is_bounded_and_never_exposed() {
        let mut error = frame(15, 0, 1, b"sensitive echoed token").unwrap();
        error.splice(4..4, 45000001_u32.to_be_bytes());
        assert_eq!(parse(&error), Err(CloudError::Service(45000001)));
        assert!(!parse(&error).unwrap_err().to_string().contains("sensitive"));
        let mut bomb = frame(15, 0, 1, &vec![b'x'; MAX_FRAME_BYTES + 1]).unwrap();
        bomb.splice(4..4, 45000001_u32.to_be_bytes());
        assert_eq!(parse(&bomb), Err(CloudError::TooLarge));
    }
    #[test]
    fn configuration_and_pcm_are_wire_compatible() {
        let cfg = configuration().unwrap();
        assert_eq!(&cfg[..4], &[0x11, 0x10, 0x11, 0]);
        let mut body = String::new();
        GzDecoder::new(&cfg[8..]).read_to_string(&mut body).unwrap();
        let json: Value = serde_json::from_str(&body).unwrap();
        assert_eq!(json["audio"]["rate"], 16000);
        assert_eq!(json["request"]["enable_nonstream"], true);
        let audio = audio(&[i16::MIN, 1, i16::MAX], true).unwrap();
        assert_eq!(&audio[..4], &[0x11, 0x22, 0x01, 0]);
        let mut pcm = Vec::new();
        GzDecoder::new(&audio[8..]).read_to_end(&mut pcm).unwrap();
        assert_eq!(pcm, vec![0, 128, 1, 0, 255, 127]);
    }
}
