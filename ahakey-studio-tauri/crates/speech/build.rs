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
        return;
    }
    let out = match env::var_os("OUT_DIR").map(PathBuf::from) {
        Some(o) => o,
        None => return,
    };
    let Some(profile) = out.ancestors().nth(3) else {
        return;
    };
    // Official sherpa-onnx-sys copies runtime libs next to normal binaries but
    // not test binaries. Tests need the same beside-exe bundle as releases.
    let tests = profile.join("deps");
    let _ = fs::create_dir_all(&tests);
    let Ok(entries) = fs::read_dir(&directory) else {
        return;
    };
    let target_ext = if target_os == "windows" { "dll" } else { "dylib" };
    for entry in entries.flatten() {
        if entry.path().extension().and_then(|ext| ext.to_str()) == Some(target_ext) {
            let _ = fs::copy(entry.path(), tests.join(entry.file_name()));
        }
    }
}
