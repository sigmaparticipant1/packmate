#!/usr/bin/env bash
set -euo pipefail

REPO="${GH_REPO:-sigmaparticipant1/packmate}"
BR="${GH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/$REPO/refs/heads/$BR/docker"

read -rp 'slot [1-20]: ' number </dev/tty
[[ "$number" =~ ^([1-9]|1[0-9]|20)$ ]] || { echo 'invalid slot' >&2; exit 1; }
printf -v n '%02d' "$number"
read -rsp 'pw: ' pw </dev/tty
printf '\n' >/dev/tty

blob="$(curl -fsSL "$RAW/slots-v3/s$n.enc" 2>/dev/null)" \
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
inner="$(curl -fsSL "$RAW/inner-v3.enc" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$key" 2>/dev/null)" \
  || { echo 'bad payload' >&2; exit 1; }
unset key
SLOT_JSON="$slot" exec bash -c "$inner"
