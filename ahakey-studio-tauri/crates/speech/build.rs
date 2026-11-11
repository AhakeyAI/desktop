use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=SHERPA_ONNX_LIB_DIR");
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os != "windows" && target_os != "macos" {
        return;
    }
    let Some(directory) = env::var_os("SHERPA_ONNX_LIB_DIR") else {
        return;
    };
    let directory = PathBuf::from(directory);
    if !directory.is_dir() {
        panic!(
            "SHERPA_ONNX_LIB_DIR does not exist or is not a directory: {}",
            directory.display()
        );
    }
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo OUT_DIR"));
    let profile = out.ancestors().nth(3).expect("Cargo profile directory");
    // Official sherpa-onnx-sys copies runtime libs next to normal binaries but
    // not test binaries. Tests need the same beside-exe bundle as releases.
    let tests = profile.join("deps");
    fs::create_dir_all(&tests).expect("Create test output directory");
    let target_ext = if target_os == "windows" {
        "dll"
    } else {
        "dylib"
    };
    for entry in fs::read_dir(&directory).expect("Read prepared speech runtime") {
        let entry = entry.expect("Read runtime file");
        if entry.path().extension().and_then(|ext| ext.to_str()) == Some(target_ext) {
            fs::copy(entry.path(), tests.join(entry.file_name()))
                .expect("Bundle native runtime beside tests");
        }
    }
}
