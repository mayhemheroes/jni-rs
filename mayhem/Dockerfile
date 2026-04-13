# Build Stage
FROM rustlang/rust:nightly AS builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN cargo install cargo-fuzz

RUN echo building instrumented harnesses && \
    bash -c "pushd fuzz && cargo fuzz build && popd" && \
    mv fuzz/target/x86_64-unknown-linux-gnu/release/typesignature /typesignature && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd fuzz && cargo build --release && popd" && \
    mv fuzz/target/release/typesignature /typesignature_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /typesignature /typesignature_no_inst /
