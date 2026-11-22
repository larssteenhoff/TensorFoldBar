#!/bin/bash
# Resumable model download into the Hugging Face cache.
#
# usage: download.sh OWNER/NAME[@REVISION] PROGRESS_FILE
#
# Every file is split into 64 MiB pieces fetched 16 at a time with HTTP range
# requests into blobs/<id>.pieces/. A piece is appended to as bytes arrive, so
# stopping this script at any point, including a reboot or a kill, keeps every
# byte already written; the next run requests only what each piece still lacks.
# A file's pieces are joined and checked against the hub's size (and SHA-256
# for LFS files) before the blob is put in place, so `tensorfold pull` finds
# every file cached afterwards. PROGRESS_FILE receives "<downloaded bytes>
# <total bytes>" every two seconds while the download runs.
set -euo pipefail

PIECE=$(( 64 * 1024 * 1024 ))
PARALLEL=16

curl_auth() {
 if [[ -n "${HF_TOKEN:-}" ]]; then curl -H "Authorization: Bearer $HF_TOKEN" "$@"; else curl "$@"; fi
}

if [[ "${1:-}" == "--fetch-piece" ]]; then
 # Internal, called by xargs below. Arguments: url piece-file first-byte last-byte
 url=$2 file=$3 first=$4 last=$5
 want=$(( last - first + 1 ))
 for attempt in $(seq 1 50); do
  have=0
  [[ -f "$file" ]] && have=$(stat -f %z "$file")
  if (( have > want )); then rm -f "$file"; have=0; fi
  (( have == want )) && exit 0
  # A stalled connection (under 100 KiB/s for 30 s) ends this attempt; the next one resumes.
  curl_auth -fsSL --speed-limit 102400 --speed-time 30 -r "$(( first + have ))-$last" "$url" >> "$file" || true
  have=$(stat -f %z "$file")
  (( have == want )) && exit 0
  sleep $(( attempt < 6 ? attempt * 2 : 10 ))
 done
 echo "  ${file##*/blobs/}: download failed after repeated attempts" >&2
 exit 1
fi

spec=${1:?usage: download.sh OWNER/NAME[@REVISION] PROGRESS_FILE}
progress=${2:?usage: download.sh OWNER/NAME[@REVISION] PROGRESS_FILE}
repo=${spec%@*}
revision=main
[[ "$spec" == *@* ]] && revision=${spec#*@}
endpoint=${HF_ENDPOINT:-https://huggingface.co}
if [[ -z "${HF_TOKEN:-}" ]]; then
 token_file=${HF_TOKEN_PATH:-${HF_HOME:-$HOME/.cache/huggingface}/token}
 if [[ -r "$token_file" ]]; then HF_TOKEN=$(<"$token_file"); fi
fi
export HF_TOKEN=${HF_TOKEN:-}
cache=${HF_HUB_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}/hub}
folder="$cache/models--${repo//\//--}"

echo "[download] $repo@$revision into $folder"
info=$(curl_auth -fsSL --retry 5 --retry-all-errors "$endpoint/api/models/$repo/revision/$revision?blobs=true")
commit=$(jq -r '.sha' <<<"$info")
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "[download] the hub did not name a commit for $repo@$revision" >&2; exit 1; }
mkdir -p "$folder/blobs" "$folder/snapshots/$commit" "$folder/refs"

# One row per file: path, blob id, size, sha256 (or -)
rows=$(jq -r '.siblings[] | [.rfilename, (.lfs.sha256 // .blobId), (.lfs.size // .size), (.lfs.sha256 // "-")] | @tsv' <<<"$info")
total=0
while IFS=$'\t' read -r path id size sha; do total=$(( total + size )); done <<<"$rows"

write_progress() {
 local done_bytes=0 path id size sha n
 while IFS=$'\t' read -r path id size sha; do
  if [[ -f "$folder/blobs/$id" ]]; then
   done_bytes=$(( done_bytes + size ))
  elif [[ -d "$folder/blobs/$id.pieces" ]]; then
   n=$(find "$folder/blobs/$id.pieces" -type f -exec stat -f %z {} + 2>/dev/null | awk '{s+=$1} END {print s+0}' || echo 0)
   done_bytes=$(( done_bytes + n ))
  fi
 done <<<"$rows"
 echo "$done_bytes $total" > "$progress.tmp" && mv -f "$progress.tmp" "$progress"
}
( while true; do write_progress; sleep 2; done ) &
reporter=$!
trap 'kill $reporter 2>/dev/null || true' EXIT

# Join a file whose pieces are all present, check it, and put the blob in place.
finish_file() {
 local id=$1 size=$2 sha=$3 dir="$folder/blobs/$1.pieces" count k
 count=$(( (size + PIECE - 1) / PIECE )); (( count == 0 )) && count=1
 for (( k = 0; k < count; k++ )); do [[ -f "$dir/$k" ]] || return 1; done
 for (( k = 0; k < count; k++ )); do cat "$dir/$k"; done > "$folder/blobs/$id.joining"
 if [[ "$(stat -f %z "$folder/blobs/$id.joining")" != "$size" ]] || { [[ "$sha" != "-" ]] && [[ "$(shasum -a 256 "$folder/blobs/$id.joining" | cut -d' ' -f1)" != "$sha" ]]; }; then
  echo "[download] $id failed its checksum; its pieces will be fetched again" >&2
  rm -rf "$dir" "$folder/blobs/$id.joining"
  return 1
 fi
 mv -f "$folder/blobs/$id.joining" "$folder/blobs/$id"
 rm -rf "$dir"
}

# An interrupted `tensorfold pull` leaves full-size blobs/<sha256>.ranges files that are often
# complete; one whose SHA-256 matches the hub is used as is instead of being fetched again.
while IFS=$'\t' read -r path id size sha; do
 [[ "$sha" == "-" || -f "$folder/blobs/$id" || ! -f "$folder/blobs/$id.ranges" ]] && continue
 [[ "$(stat -f %z "$folder/blobs/$id.ranges")" == "$size" ]] || continue
 echo "  $path: checking a file left by tensorfold pull"
 if [[ "$(shasum -a 256 "$folder/blobs/$id.ranges" | cut -d' ' -f1)" == "$sha" ]]; then
  mv -f "$folder/blobs/$id.ranges" "$folder/blobs/$id"
  rm -rf "$folder/blobs/$id.pieces"
  echo "  $path: reused"
 fi
done <<<"$rows"

# Queue every piece that is not complete yet, file by file in hub order.
while IFS=$'\t' read -r path id size sha; do
 [[ -f "$folder/blobs/$id" ]] && continue
 dir="$folder/blobs/$id.pieces"
 mkdir -p "$dir"
 encoded=$(jq -rn --arg p "$path" '$p | split("/") | map(@uri) | join("/")')
 url="$endpoint/$repo/resolve/$commit/$encoded"
 if (( size == 0 )); then : > "$dir/0"; continue; fi
 for (( first = 0, k = 0; first < size; first += PIECE, k++ )); do
  last=$(( first + PIECE - 1 )); (( last >= size )) && last=$(( size - 1 ))
  have=0; [[ -f "$dir/$k" ]] && have=$(stat -f %z "$dir/$k")
  (( have == last - first + 1 )) && continue
  printf '%s\0%s\0%s\0%s\0' "$url" "$dir/$k" "$first" "$last"
 done
done <<<"$rows" | xargs -0 -n 4 -P "$PARALLEL" /bin/bash "$0" --fetch-piece &
queue=$!
# Stopping this script (TensorFold Bar's Stop or Quit) also stops its piece fetchers; the
# pieces stay on disk for the next run. `wait` lets the trap run while the queue is busy.
stop_fetchers() {
 kill "$queue" 2>/dev/null || true
 pkill -TERM -f "resolve/$commit/" 2>/dev/null || true
 kill $reporter 2>/dev/null || true
 echo "[download] stopped; the next start continues from here"
 exit 143
}
trap stop_fetchers TERM INT HUP
wait "$queue" || true
trap - TERM INT HUP

failed=0
while IFS=$'\t' read -r path id size sha; do
 if [[ ! -f "$folder/blobs/$id" ]]; then finish_file "$id" "$size" "$sha" || { failed=1; continue; }; fi
 link="$folder/snapshots/$commit/$path"
 mkdir -p "$(dirname "$link")"
 depth=$(( $(tr -cd '/' <<<"$path" | wc -c) + 2 ))
 ln -sfn "$(printf '../%.0s' $(seq 1 $depth))blobs/$id" "$link"
done <<<"$rows"
(( failed == 0 )) || { echo "[download] some files are incomplete; run it again to continue" >&2; exit 1; }
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || echo -n "$commit" > "$folder/refs/$revision"
write_progress
echo "[download] complete: $repo@$commit"
