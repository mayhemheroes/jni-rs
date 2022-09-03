#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &str| {
    _ = jni::signature::TypeSignature::from_str(data);
});
