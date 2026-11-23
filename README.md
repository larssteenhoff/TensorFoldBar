# TensorFold Bar

A macOS menu bar controller for [TensorFold](https://github.com/ashhart/TensorFold) on Apple Silicon.

![TensorFold Bar menu with server controls and available RAM](screenshot.png)

## Install

On an Apple Silicon Mac, install the [latest release](https://github.com/larssteenhoff/TensorFoldBar/releases/latest) from Terminal:

```bash
curl -fL -o /tmp/TensorFoldBar.zip https://github.com/larssteenhoff/TensorFoldBar/releases/latest/download/TensorFoldBar-mac-arm64.zip && mkdir -p ~/Applications && ditto -x -k /tmp/TensorFoldBar.zip ~/Applications && open ~/Applications/"TensorFold Bar.app"
```

Run it again to update. The app is ad hoc signed, not notarized by Apple: files downloaded with curl are not quarantined, so it opens directly, while a copy downloaded in a browser is blocked until you allow it under System Settings › Privacy & Security. To build it yourself instead, see [Build](#build).

## Use with Harness

[Harness](https://github.com/larssteenhoff/deepseek-harness) — a DeepSeek Harness fork with a desktop app — uses this app's server as its default model and has a TensorFold button that opens this app. To install both on an Apple Silicon Mac with Node.js 24.9 or newer:

```bash
git clone https://github.com/larssteenhoff/deepseek-harness.git ~/deepseek-harness
cd ~/deepseek-harness
./install-mac.sh
```

The script clones this repository into `~/TensorFoldBar`, builds both apps, installs them in `~/Applications`, and points Harness at `http://127.0.0.1:8080/v1`. Choosing a window in the Context menu also updates Harness's model entry.

## Controls

Opening TensorFold Bar automatically starts the saved model: it checks/downloads the checkpoint, then starts the local server. Pause, Stop, and manual Start remain available in the menu. Opening the app with a newly selected model can start a large download if its weights are not cached.

- Model: choose a checkpoint from the submenu. Stop the server before switching; the selected repository is remembered.
- Context: choose the server's context window, 4K to 1M tokens. A coding agent such as DeepSeek Harness needs more than 16K: its system prompt and tools alone take about 11K. Only windows the selected model declares (its `max_position_embeddings`) are listed: 256K for the Qwen models, 1M for GLM-5.3 Flash. Choosing a new window restarts a running server; switching to a model with a shorter limit lowers the setting to fit. The choice is remembered and also written to DeepSeek Harness's TensorFold model entry (`contextWindow` in `~/.dsh/profiles/desktop/cordis.patch.yml`), so restart Harness to pick it up. Longer windows take more memory for the KV cache and slow long prompts.
- Start: download the selected checkpoint, have TensorFold check it, then launch its local server. The starter Qwen3.5-2B checkpoint is revision-pinned; other models use their repository's current default revision. Large models can require over 100 GB of downloads and substantial loading time.
- Pause / Resume: suspend or resume the server process. Pausing retains model memory and pauses requests.
- Stop: terminate the server and release its memory, or stop a download in progress.
- Download progress: while a checkpoint downloads, the menu bar shows its percentage and the status row shows downloaded and total GiB.
- Menu bar: shows `TF · <RAM> GB available` at a fixed width, adding a pause mark while paused and the percentage while a model downloads.
- Available RAM: estimated reclaimable memory (free + inactive + speculative pages), refreshed every three seconds. This is an estimate, not Activity Monitor's memory pressure metric.
- Update TensorFold to latest: available when stopped; fetch the latest upstream Apple Silicon release, verify its published SHA-256 checksum, and replace the bundled engine.
- Copy API URL and Show log.
- Benchmark: sends one local request for up to the selected output token limit. Choose 32–4,096 tokens from the Output tokens submenu (default: 64); the choice is remembered. While measuring, the menu says “Benchmark running…”; result rows appear only after successful completion. It measures the model the server has loaded (`local-model`), and the first result row names that model and the context window, for example “Benchmark (Qwen3.8 Flash Next · 6-bit, 64K)”. Results include overall output tokens/second, elapsed seconds, prefill speed, and time to first token. Prefill and first-token times come from TensorFold's per-response `tensorfold.prefill_seconds` and `tensorfold.time_to_first_token` fields. Prefill speed uses uncached prompt tokens; fully cached prompts are labeled, and missing timing/count fields show unavailable. Overall speed includes prompt processing and generation. This is an end-to-end measurement; cached prompts affect results. Results stay local. Stop or Quit cancels the benchmark.

API URL: `http://127.0.0.1:8080/v1`; model name: the served id, or `local-model`.
Logs: `~/Library/Logs/TensorFoldBar.log`.

## Downloads

`download.sh` fetches checkpoints into the standard Hugging Face cache (`~/.cache/huggingface/hub`, or `HF_HUB_CACHE`/`HF_HOME`). Each file is split into 64 MiB pieces fetched 16 at a time with HTTP range requests; a piece keeps every byte written, so Stop, Quit, a crash, or a restart of the Mac loses nothing, and the next Start requests only the missing bytes. A finished file is joined and checked against the hub's size and SHA-256 before it is put in place, after which `tensorfold pull` confirms the cached files and the server starts. `HF_TOKEN`, or the token saved by `hf auth login`, is sent for gated repositories.

TensorFold's own `pull` keeps only finished files when it is stopped, so the app no longer uses it to download. If TensorFold Bar opens while a download started by an earlier copy is still running, it shows that download's progress instead of starting a second one, and asks before stopping a `tensorfold pull`.

## Model choices

| Menu choice | Checkpoint | Scope |
| --- | --- | --- |
| Qwen3.5 2B, 4-bit | `mlx-community/Qwen3.5-2B-MLX-4bit` | Existing starter model, pinned revision |
| Qwen3.8 27B, 4-bit | `TensorFold/Qwen3.8-27B-MLX-4bit` | Native Metal |
| Qwen3.8 Flash Next, 4-bit | `TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP` | Native Metal, includes MTP |
| Qwen3.8 Flash Next, 6-bit | `TensorFold/Qwen3.8-Flash-Next-MLX-6bit-MTP` | Native Metal, M5 Ultra checked upstream |
| GLM-5.3 Flash, 4-bit | `TensorFold/GLM-5.3-Flash-MLX-4bit-MTP` | Experimental on a single Mac; upstream qualifies two M5 Ultras |
| DeepSeek Flash | Informational menu entry | Native release does not yet serve DeepSeek; the old Python 0.6.6 recipe uses a different engine |

Every model serves at the same API URL under its own id (for example `qwen3.8-flash-next`), with `local-model` as an alias, with the context chosen in the Context menu (default 64K), one stream, and thinking off. Inkling 2 Mini (experimental) also reads images (`--vision`) and keeps its reasoning on; it runs on a TensorFold built from pull requests #4337 and #4124 in `~/GitHub/TensorFold-inkling`, because the bundled runtime cannot load it. The benchmark uses this alias as well. Model choices do not automatically download optional external drafters. Default TensorFold memory admission limits are preserved; choosing a larger model does not override them. GLM's single-Mac path may refuse to load and has not been validated by this app.

Support references: [upstream supported models](https://github.com/ashhart/TensorFold/blob/main/docs/supported-models.md), [Mac runbook](https://github.com/ashhart/TensorFold/blob/main/RUNBOOK.md), and [DeepSeek recipe and engine distinction](https://github.com/ashhart/TensorFold/blob/main/docs/recipes/deepseek-v4-flash.md). These are the documented limits when the picker was added, not a guarantee for future releases.

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

Initial prototype. AppleScript source compiles, but launch and server controls still need validation on the target Mac. “Running” currently means the server process started; the model may still be loading. Updates require stopping the server first. Closing the app terminates the server it owns and stops its download, which resumes on the next Start.

TensorFold and downloaded models retain their upstream licenses. Model weights and third-party runtime binaries are not included in this source repository.
