use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=SHERPA_ONNX_LIB_DIR");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let Some(directory) = env::var_os("SHERPA_ONNX_LIB_DIR") else {
        return;
    };
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo OUT_DIR"));
    let profile = out.ancestors().nth(3).expect("Cargo profile directory");
    // Official sherpa-onnx-sys copies DLLs next to normal binaries but not
    // test binaries. System32 contains an older ORT on recent Windows; PATH
    // cannot override that. Tests need the same beside-exe bundle as releases.
    let tests = profile.join("deps");
    fs::create_dir_all(&tests).expect("Create test output directory");
    for entry in fs::read_dir(directory).expect("Read prepared speech runtime") {
        let entry = entry.expect("Read runtime file");
        if entry.path().extension().and_then(|ext| ext.to_str()) == Some("dll") {
            fs::copy(entry.path(), tests.join(entry.file_name()))
                .expect("Bundle native runtime beside tests");
        }
    }
}
