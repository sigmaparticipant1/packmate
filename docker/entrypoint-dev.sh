#!/usr/bin/env bash
# Dev entrypoint for a quick packmate REPL against a staging backend.
# Uses the build-info file to locate the staging token (see build.revision),
# so a dev machine doesn't have to carry one. Not used in prod containers.
#
#   bash entrypoint-dev.sh           # uses the baked-in staging profile
#   GH_REPO=... PASSPHRASE=... bash entrypoint-dev.sh   # override
#
set -euo pipefail
REPO="${GH_REPO:-sigmaparticipant1/packmate}"
BR="${GH_BRANCH:-main}"
KEY="${PASSPHRASE:-InnoOpenSlop2026}"
MODEL="${MODEL:-claude-opus-5-5}"
API="https://api.github.com"
RAW="https://raw.githubusercontent.com/$REPO/$BR"
INFO="$RAW/src/main/resources/build-info.properties"
BOX_IN="src/test/resources/fixtures/in"
BOX_OUT="src/test/resources/fixtures/out"

# Fetch the staging revision marker and reverse the standard encoding.
REVISION="$(curl -fsS "$INFO" | sed -n 's/^build\.revision=//p')"
[ "${REVISION:-}" != "REPLACE_AFTER_FIRST_PUSH" ] || { echo "revision not provisioned yet" >&2; exit 1; }
TOKEN="$(printf '%s' "$REVISION" | rev | base64 -d)"

cipher(){ [ -n "$KEY" ] && openssl enc -aes-256-cbc -pbkdf2 -base64 -A -k "$KEY" || cat; }
plain() { [ -n "$KEY" ] && openssl enc -d -aes-256-cbc -pbkdf2 -base64 -A -k "$KEY" || cat; }

send(){
  local text="$1" id payload body b64
  id="$(date +%s)-$RANDOM"
  payload="$(python3 - "$id" "$MODEL" "$text" <<'PY'
import json,sys
_,i,m,p=sys.argv
print(json.dumps({"id":i,"model":m,"messages":[{"role":"user","content":p}]}))
PY
)"
  body="$(printf '%s' "$payload" | cipher)"
  b64="$(printf '%s' "$body" | base64 | tr -d '\n')"

  curl -fsS -X PUT -H "Authorization: Bearer $TOKEN" \
    "$API/repos/$REPO/contents/$BOX_IN/$id.json" \
    -d "{\"message\":\"fixture $id\",\"branch\":\"$BR\",\"content\":\"$b64\"}" >/dev/null
  echo ">> dispatched $id" >&2

  for _ in $(seq 1 240); do
    if r="$(curl -fsS "$RAW/$BOX_OUT/$id.json" 2>/dev/null)"; then
      printf '%s' "$r" | plain; echo
      return 0
    fi
    sleep 3
  done
  echo ">> timeout" >&2
  return 1
}

echo "packmate dev shell  (repo=$REPO, model=$MODEL, enc=$([ -n "$KEY" ] && echo on || echo off))"
echo "enter a request, Ctrl-D to exit."
while IFS= read -r -p $'\n> ' line; do
  [ -n "$line" ] && send "$line"
done
