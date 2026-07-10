#!/bin/sh
set -eu

TARGET_DIR="${CODEX_MOON_TARGET_DIR:-_build}"

rm -f "$TARGET_DIR/.moon-lock" .mooncakes/.moon-lock
find "$TARGET_DIR" -name 'test.moon_db' -o -name 'test.moon_db-shm' -o -name 'test.moon_db-wal' 2>/dev/null | while IFS= read -r path; do
  rm -f "$path"
done
exec moon --target-dir "$TARGET_DIR" "$@"
