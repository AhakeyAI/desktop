use ahakey_speech::{Recognizer, RecognizerConfig, SAMPLE_RATE};
use std::{path::PathBuf, time::Instant};

/// Real weights and an official fixed WAV are supplied explicitly. No test
/// downloads models or opens a microphone. Run this gate before packaging.
#[test]
#[ignore = "Requires AHAKEY_TEST_MODEL_DIR and AHAKEY_TEST_ZH_WAV (official pinned SenseVoice fixture)"]
fn native_sensevoice_known_answer() {
    let model = PathBuf::from(
        std::env::var_os("AHAKEY_TEST_MODEL_DIR").expect("Set AHAKEY_TEST_MODEL_DIR"),
    );
    let wav = std::env::var_os("AHAKEY_TEST_ZH_WAV").expect("Set AHAKEY_TEST_ZH_WAV");
    let mut reader = hound::WavReader::open(wav).unwrap();
    assert_eq!(reader.spec().sample_rate, SAMPLE_RATE);
    assert_eq!(reader.spec().channels, 1);
    let samples: Vec<f32> = reader
        .samples::<i16>()
        .map(|sample| sample.unwrap() as f32 / 32768.)
        .collect();
    let start = Instant::now();
    let recognizer = Recognizer::new(RecognizerConfig {
        model_dir: model,
        threads: 4,
    })
    .unwrap();
    eprintln!("Native SenseVoice load+verify: {:?}", start.elapsed());
    let start = Instant::now();
    let result = recognizer.decode(&samples, SAMPLE_RATE).unwrap();
    eprintln!(
        "Native SenseVoice {:.2}s audio: {:?}; transcript: {}",
        samples.len() as f64 / SAMPLE_RATE as f64,
        start.elapsed(),
        result
    );
    assert_eq!(result, "开饭时间早上9点至下午5点。");
    let mut partials = Vec::new();
    for seconds in [1, 2, 3, 4] {
        let length = (seconds * SAMPLE_RATE as usize).min(samples.len());
        let partial = recognizer.decode(&samples[..length], SAMPLE_RATE).unwrap();
        if !partial.is_empty() && partials.last() != Some(&partial) {
            partials.push(partial);
        }
    }
    eprintln!("Provisional updates: {}", partials.len());
    assert!(
        partials.len() >= 2,
        "Real audio should produce changing provisional text"
    );
    assert!(recognizer
        .decode(&[0.; 1600], SAMPLE_RATE)
        .unwrap()
        .is_empty());
    assert!(recognizer.decode(&samples, 48000).is_err());
}

#[test]
#[ignore = "Requires AHAKEY_TEST_MODEL_DIR; imports the existing pinned model without downloading"]
fn verified_model_import() {
    use ahakey_speech::{CancellationToken, ModelStore};
    use std::cell::Cell;
    let source = PathBuf::from(
        std::env::var_os("AHAKEY_TEST_MODEL_DIR").expect("Set AHAKEY_TEST_MODEL_DIR"),
    );
    let target = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target");
    let directory = tempfile::tempdir_in(target).unwrap();
    let store = ModelStore::new(directory.path().join("model"));
    let last_progress = Cell::new(0.);
    store
        .import_from(&source, &CancellationToken::new(), |progress| {
            assert!(progress >= last_progress.get() && progress <= 1.);
            last_progress.set(progress);
        })
        .unwrap();
    assert_eq!(last_progress.get(), 1.);
    assert!(store.is_installed());
    store.verify().unwrap();
}
