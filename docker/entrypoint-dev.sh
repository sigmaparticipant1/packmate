#!/usr/bin/env bash
set -euo pipefail

REPO="${GH_REPO:-sigmaparticipant1/packmate}"
BR="${GH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/$REPO/refs/heads/$BR/docker"

read -rsp 'pw: ' pw </dev/tty
printf '\n' >/dev/tty

slot=''
for i in {1..10}; do
  printf -v n '%02d' "$i"
  blob="$(curl -fsSL "$RAW/slots/s$n.enc" 2>/dev/null)" || continue
  candidate="$(printf '%s' "$blob" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$pw" 2>/dev/null)" || continue
  if SLOT_JSON="$candidate" python3 -c '
import json,os,re,sys
s=json.loads(os.environ["SLOT_JSON"])
sys.exit(0 if all(isinstance(s.get(k),str) and s[k] for k in "abcde") and re.fullmatch(r"[a-z0-9]+",s["d"]) else 1)
' 2>/dev/null; then
    slot="$candidate"
    break
  fi
done
unset pw candidate blob i n
[ -n "$slot" ] || { echo 'bad pw or slot' >&2; exit 1; }

key="$(SLOT_JSON="$slot" python3 -c 'import json,os; print(json.loads(os.environ["SLOT_JSON"])["a"])')"
inner="$(curl -fsSL "$RAW/inner.enc" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$key" 2>/dev/null)" \
  || { echo 'bad payload' >&2; exit 1; }
unset key
SLOT_JSON="$slot" exec bash -c "$inner"
