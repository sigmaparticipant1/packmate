#!/usr/bin/env bash
set -euo pipefail

BR="${PACKMATE_BRANCH:-main}"
GH_REPO="${GH_REPO:-sigmaparticipant1/packmate}"
GL_PROJECT="${GITLAB_PROJECT_ID:-89252376}"
YANDEX="https://functions.yandexcloud.net/d4efv0ehkpji3j5m5ha1"
GOOGLE="https://script.google.com/macros/s/AKfycbwn1PWgrdPKsQ7IFvxzMCSOpWdkAg8zi3G9WkMalEvKOjf5Crm1Sjc361_8Rv0Oi9ci/exec"
SOURCES=("${PACKMATE_GET_GATEWAY:-$YANDEX}" "$YANDEX" "$GOOGLE" github gitlab)

fetch_blob() {
  local source="$1" path="$2" encoded
  case "$source" in
    github)
      curl -fsSL --connect-timeout 5 --max-time 20 \
        "https://raw.githubusercontent.com/$GH_REPO/refs/heads/$BR/$path" 2>/dev/null ;;
    gitlab)
      encoded="${path//\//%2F}"
      curl -fsSL --connect-timeout 5 --max-time 20 \
        "https://gitlab.com/api/v4/projects/$GL_PROJECT/repository/files/$encoded/raw?ref=$BR" 2>/dev/null ;;
    *)
      curl -fsSLG --connect-timeout 5 --max-time 20 \
        --data-urlencode 'op=read' --data-urlencode "path=$path" "$source" 2>/dev/null \
        | python3 -c 'import base64,json,sys; sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)["content"]))' 2>/dev/null ;;
  esac
}

read -rp 'slot [1-20]: ' number </dev/tty
[[ "$number" =~ ^([1-9]|1[0-9]|20)$ ]] || { echo 'invalid slot' >&2; exit 1; }
printf -v n '%02d' "$number"
read -rsp 'pw: ' pw </dev/tty
printf '\n' >/dev/tty

slot_path="docs/.assets/4a65d9a316905404/s$n.enc"
slot=''
for source in "${SOURCES[@]}"; do
  blob="$(fetch_blob "$source" "$slot_path")" || continue
  candidate="$(printf '%s' "$blob" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$pw" 2>/dev/null)" || continue
  if SLOT_JSON="$candidate" SLOT_LABEL="s$n" python3 -c '
import json,os,sys
s=json.loads(os.environ["SLOT_JSON"])
sys.exit(0 if all(isinstance(s.get(k),str) and s[k] for k in "abcdef") and s["d"] == os.environ["SLOT_LABEL"] else 1)
' 2>/dev/null; then
    slot="$candidate"
    break
  fi
done
[[ -n "$slot" ]] || { echo 'slot unavailable or bad pw' >&2; exit 1; }
unset pw blob candidate number n

key="$(SLOT_JSON="$slot" python3 -c 'import json,os; print(json.loads(os.environ["SLOT_JSON"])["a"])')"
inner=''
for source in "${SOURCES[@]}"; do
  inner_blob="$(fetch_blob "$source" 'docker/inner-v3.enc')" || continue
  candidate="$(printf '%s' "$inner_blob" | openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -pass fd:3 3<<<"$key" 2>/dev/null)" || continue
  if [[ "$candidate" == '#!'* ]]; then
    inner="$candidate"
    break
  fi
done
[[ -n "$inner" ]] || { echo 'payload unavailable' >&2; exit 1; }
unset key inner_blob candidate source
SLOT_JSON="$slot" exec bash -c "$inner" </dev/tty
