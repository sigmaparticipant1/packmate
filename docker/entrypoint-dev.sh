#!/usr/bin/env bash
set -euo pipefail

GATEWAY="${PACKMATE_GET_GATEWAY:-https://functions.yandexcloud.net/d4efv0ehkpji3j5m5ha1}"

read -rp 'slot [1-20]: ' number </dev/tty
[[ "$number" =~ ^([1-9]|1[0-9]|20)$ ]] || { echo 'invalid slot' >&2; exit 1; }
printf -v n '%02d' "$number"
read -rsp 'pw: ' pw </dev/tty
printf '\n' >/dev/tty

blob="$(curl -fsSLG --data-urlencode 'op=read' --data-urlencode "path=docs/.assets/4a65d9a316905404/s$n.enc" "$GATEWAY" 2>/dev/null | python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["content"]).decode())')" \
  || { echo 'slot unavailable' >&2; exit 1; }
slot="$(printf '%s' "$blob" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$pw" 2>/dev/null)" \
  || { echo 'bad pw' >&2; exit 1; }
if ! SLOT_JSON="$slot" SLOT_LABEL="s$n" python3 -c '
import json,os,sys
s=json.loads(os.environ["SLOT_JSON"])
sys.exit(0 if all(isinstance(s.get(k),str) and s[k] for k in "abcde") and s["d"] == os.environ["SLOT_LABEL"] else 1)
' 2>/dev/null; then
  echo 'bad pw or slot' >&2
  exit 1
fi
unset pw blob number n

key="$(SLOT_JSON="$slot" python3 -c 'import json,os; print(json.loads(os.environ["SLOT_JSON"])["a"])')"
inner_blob="$(curl -fsSLG --data-urlencode 'op=read' --data-urlencode 'path=docker/inner-v3.enc' "$GATEWAY" | python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["content"]).decode())')" \
  || { echo 'payload unavailable' >&2; exit 1; }
if [[ "$inner_blob" == \{* ]]; then
  inner_blob="$(printf '%s' "$inner_blob" | python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["content"]).decode())')"
fi
inner="$(printf '%s' "$inner_blob" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$key" 2>/dev/null)" \
  || { echo 'bad payload' >&2; exit 1; }
unset key inner_blob
SLOT_JSON="$slot" exec bash -c "$inner"
