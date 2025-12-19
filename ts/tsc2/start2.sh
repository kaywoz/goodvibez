#!/usr/bin/env bash
set -euo pipefail

# where to write logs
LOGDIR="/var/log/tsc2"
mkdir -p "$LOGDIR"
chown "$(whoami)" "$LOGDIR" 2>/dev/null || true

# Adjust bind address: use 127.0.0.1 for local-only, 0.0.0.0 to expose to network
BIND_ADDR="0.0.0.0"

# Start your python web app (adjust path to webserver.py)
echo "Starting webserver.py...e.g exit"
nohup sudo python3 /opt/tsc2/webserver.py \
  > "$LOGDIR/webserver.out" 2> "$LOGDIR/webserver.err" &

# Start a simple http.server on 8000 (serves current dir)
echo "Starting http.server on :8000...e.g loot"
nohup sudo python3 -m http.server 8000 --bind "$BIND_ADDR" \
  > "$LOGDIR/http8000.out" 2> "$LOGDIR/http8000.err" &

# Serve the keys directory on port 8001
KEYDIR="/opt/tsc2/keys"
if [[ ! -d "$KEYDIR" ]]; then
  echo "ERROR: keys directory $KEYDIR does not exist" >&2
  exit 1
fi

echo "Starting http.server on :8001 serving $KEYDIR... e.g keys"
nohup sudo python3 -m http.server 8001 --bind "$BIND_ADDR" --directory "$KEYDIR" \
  > "$LOGDIR/http8001.out" 2> "$LOGDIR/http8001.err" &

# Print PIDs of the background jobs (last 3 background jobs)
sleep 0.1
echo "Started processes (recent pids):"
ps -o pid,cmd -u "$(whoami)" | tail -n 10

echo "Logs: $LOGDIR"
