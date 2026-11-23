#!/bin/bash
# Point a DeepSeek Harness profile at the model TensorFold Bar serves.
#
# usage: harness-sync.sh PATCH_FILE NAME CONTEXT_TOKENS INPUTS
#
# PATCH_FILE is a profile's cordis.patch.yml (a YAML array of patch entries). A profile without a
# `tensorfold` provider gets the two entries that use it: the default model and the provider, at
# http://127.0.0.1:8080/v1 with model id `local-model` (the alias every Bar model answers to). Then
# the provider's model entry takes NAME, CONTEXT_TOKENS and INPUTS ("text" or "text,image"). The
# file is replaced only when its content changes; the first change keeps a copy as PATCH_FILE.bak.
set -euo pipefail

patch=${1:?usage: harness-sync.sh PATCH_FILE NAME CONTEXT_TOKENS INPUTS}
name=${2:?usage: harness-sync.sh PATCH_FILE NAME CONTEXT_TOKENS INPUTS}
context=${3:?usage: harness-sync.sh PATCH_FILE NAME CONTEXT_TOKENS INPUTS}
inputs=${4:?usage: harness-sync.sh PATCH_FILE NAME CONTEXT_TOKENS INPUTS}
[[ "$context" =~ ^[0-9]+$ ]] || { echo "[harness] context must be a token count, not '$context'" >&2; exit 2; }
[[ -f "$patch" ]] || exit 0

work=$(mktemp "${patch}.XXXXXX")
trap 'rm -f "$work"' EXIT

if grep -q '^ *tensorfold: *$' "$patch"; then
 cp "$patch" "$work"
else
 # Drop an empty list (`[]`) so the entries below form the array.
 grep -v '^\[\] *$' "$patch" > "$work" || true
 cat >> "$work" <<'EOF'
# TensorFold Bar's local server; TensorFold Bar keeps this model entry in step with the model it serves.
- id: agent-default-model
  name: '@deepseek-ai/dsh-agent-default-model'
  config:
    provider: tensorfold
    model: local-model
- id: llm-pi-ai
  name: '@deepseek-ai/dsh-llm-pi-ai'
  config:
    providers:
      tensorfold:
        displayName: TensorFold (local)
        api: openai-completions
        baseURL: http://127.0.0.1:8080/v1
        headers:
          Authorization: Bearer local
        models:
          - id: local-model
            name: TensorFold
            contextWindow: 65536
            maxTokens: 8192
            input:
              - text
            reasoningEfforts: false
        compat:
          supportsStore: false
          supportsDeveloperRole: false
          maxTokensField: max_tokens
        retryPolicy:
          mode: normal
          maxRetries: 0
EOF
fi

# Inside the tensorfold provider's `local-model` entry: set name and contextWindow, and replace the
# input list's items. The entry ends at the next key indented no deeper than `- id:`.
awk -v name="$name" -v context="$context" -v inputs="$inputs" '
 /^ *tensorfold: *$/ { provider = 1 }
 provider && /^ *- id: local-model *$/ { model = 1; depth = index($0, "-"); print; next }
 model {
  indent = match($0, /[^ ]/)
  if (indent > 0 && indent <= depth) { model = 0; provider = 0; skipping = 0 }
 }
 model && skipping {
  if ($0 ~ /^ *- /) next
  skipping = 0
 }
 model && /^ *name:/ { sub(/name:.*/, "name: " name); print; next }
 model && /^ *contextWindow:/ { sub(/contextWindow:.*/, "contextWindow: " context); print; next }
 model && /^ *input: *$/ {
  print
  pad = substr($0, 1, match($0, /[^ ]/) - 1) "  "
  n = split(inputs, kinds, ",")
  for (i = 1; i <= n; i++) print pad "- " kinds[i]
  skipping = 1
  next
 }
 { print }
' "$work" > "$work.out" && mv -f "$work.out" "$work"

if ! cmp -s "$patch" "$work"; then
 [[ -f "$patch.bak" ]] || cp "$patch" "$patch.bak"
 mv -f "$work" "$patch"
 echo "[harness] $patch now names $name ($context tokens, $inputs)"
fi
