#![no_main]
use std::str::FromStr;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &str| {
    let _ = jni::signature::JavaType::from_str(data);
    let _ = jni::signature::RuntimeMethodSignature::from_str(data);
});
