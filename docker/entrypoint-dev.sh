#!/usr/bin/env bash
set -euo pipefail

PROJECT="${GITLAB_PROJECT_ID:-89252376}"
BR="${GITLAB_BRANCH:-main}"
API="https://gitlab.com/api/v4/projects/$PROJECT/repository/files"

read -rp 'slot [1-20]: ' number </dev/tty
[[ "$number" =~ ^([1-9]|1[0-9]|20)$ ]] || { echo 'invalid slot' >&2; exit 1; }
printf -v n '%02d' "$number"
read -rsp 'pw: ' pw </dev/tty
printf '\n' >/dev/tty

blob="$(curl -fsSL "$API/docs%2F.assets%2F4a65d9a316905404%2Fs$n.enc/raw?ref=$BR" 2>/dev/null)" \
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
url="$API/docker%2Finner-v3.enc/raw?ref=$BR&tick=$RANDOM$$"
inner_blob="$(curl -fsSL "$url")" \
  || { echo 'payload unavailable' >&2; exit 1; }
if [[ "$inner_blob" == \{* ]]; then
  inner_blob="$(printf '%s' "$inner_blob" | python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["content"]).decode())')"
fi
inner="$(printf '%s' "$inner_blob" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$key" 2>/dev/null)" \
  || { echo 'bad payload' >&2; exit 1; }
unset key inner_blob url
SLOT_JSON="$slot" exec bash -c "$inner"
