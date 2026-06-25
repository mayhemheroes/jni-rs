#![no_main]
use std::str::FromStr;
use libfuzzer_sys::fuzz_target;

// Fuzz the jni crate's pure-Rust JNI type-signature parsers (no JVM needed).
fuzz_target!(|data: &str| {
    let _ = jni::signature::JavaType::from_str(data);
    let _ = jni::signature::RuntimeMethodSignature::from_str(data);
});
