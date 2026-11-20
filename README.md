# TensorFold Bar

A macOS menu bar controller for [TensorFold](https://github.com/ashhart/TensorFold) on Apple Silicon.

![TensorFold Bar menu with server controls and available RAM](screenshot.png)

## Controls

- Start: download/check the pinned Qwen3.5-2B MLX 4-bit model, then launch its local server.
- Pause / Resume: suspend or resume the server process. Pausing retains model memory and pauses requests.
- Stop: terminate the server and release its memory.
- Available RAM: estimated reclaimable memory (free + inactive + speculative pages), refreshed every three seconds. This is an estimate, not Activity Monitor's memory pressure metric.
- Update TensorFold to latest: available when stopped; fetch the latest upstream Apple Silicon release, verify its published SHA-256 checksum, and replace the bundled engine.
- Copy API URL and Show log.
- Benchmark: sends one local request for up to the selected output token limit. Choose 32–4,096 tokens from the Output tokens submenu (default: 64); the choice is remembered. While measuring, the menu says “Benchmark running…”; result rows appear only after successful completion. Results include overall output tokens/second, elapsed seconds, prefill speed, and time to first token. Prefill and first-token times come from TensorFold's per-response `tensorfold.prefill_seconds` and `tensorfold.time_to_first_token` fields. Prefill speed uses uncached prompt tokens; fully cached prompts are labeled, and missing timing/count fields show unavailable. Overall speed includes prompt processing and generation. This is an end-to-end measurement; cached prompts affect results. Results stay local. Stop or Quit cancels the benchmark.

API URL: `http://127.0.0.1:8080/v1`; model name: `local-model`.
Logs: `~/Library/Logs/TensorFoldBar.log`.

## Build

Requires an Apple Silicon Mac, macOS Cocoa/AppleScript support, and the system Ruby and command-line utilities. No Swift compiler is needed.

```bash
bash build.sh
open "dist/TensorFold Bar.app"
```

Building downloads the latest TensorFold runtime from its upstream GitHub release. To bundle an already extracted runtime instead:

```bash
TENSORFOLD_RUNTIME="/absolute/path/to/tensorfold-1.3.2-macos-arm64" bash build.sh
```

Move the resulting app to a writable location. Updates modify its bundled runtime; managed or read-only installations may prevent updates. The build uses local ad hoc signing, not Apple notarization.

## Status

Initial prototype. AppleScript source compiles, but launch and server controls still need validation on the target Mac. “Running” currently means the server process started; the model may still be loading. Updates require stopping the server first. Closing the app terminates the server it owns.

TensorFold and downloaded models retain their upstream licenses. Model weights and third-party runtime binaries are not included in this source repository.
