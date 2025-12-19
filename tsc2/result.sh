#!/usr/bin/env bash
set -euo pipefail

# change these if needed
LOGFILE="/opt/tsc2/server.log"
WEBROOT="/opt/tsc2"        # or wherever your site is served from
OUT_JSON="$WEBROOT/dump.json"

# Remove old dump file
sudo rm -f "$OUT_JSON"

# Grab the last Base64 block that follows a 'Body:' line, strip whitespace, decode to JSON
b64_last_block="$(
  awk '
    /^.*Body:/ {capture=1; buf=""; next}       # start capturing after "Body:"
    capture && NF==0 {last=buf; capture=0}     # blank line ends the block
    capture {gsub(/[ \t\r\n]/,""); buf=buf $0} # strip whitespace, accumulate
    END {
      if (capture) { last=buf }                # handle EOF without trailing blank
      print last
    }
  ' "$LOGFILE"
)"

if [[ -z "$b64_last_block" ]]; then
  echo "No Base64 body found in $LOGFILE" >&2
  exit 1
fi

# Decode (GNU base64 uses --decode; BusyBox/macOS use -d). Try both.
decode_ok=false
if echo -n "$b64_last_block" | base64 --decode > "$OUT_JSON" 2>/dev/null; then
  decode_ok=true
elif echo -n "$b64_last_block" | base64 -d > "$OUT_JSON" 2>/dev/null; then
  decode_ok=true
fi

if ! $decode_ok; then
  echo "Base64 decode failed (unknown base64 flavor?)." >&2
  exit 2
fi

# Optionally set readable perms
chmod 0644 "$OUT_JSON"

echo "Decoded JSON written to $OUT_JSON"
