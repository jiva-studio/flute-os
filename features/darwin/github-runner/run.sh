#!/usr/bin/env bash
# GitHub Actions self-hosted runner loop (ephemeral mode).
#
# Args:
#   $1 — runner name (also subdir under $HOME/.github-runner)
#   $2 — GitHub URL (org: https://github.com/<org>, repo: https://github.com/<owner>/<repo>)
#   $3 — path to file containing PAT (admin:org or repo scope)
#   $4 — comma-separated runner labels
#
# Flow per invocation (launchd KeepAlive=true restarts after each job):
#   1. Read PAT, exchange it for a fresh registration token via API.
#   2. Configure runner (--ephemeral, --replace).
#   3. Run one job, exit. launchd restarts → loop.
set -euo pipefail

NAME="$1"
URL="$2"
PAT_FILE="$3"
LABELS="$4"

# launchd cd'd here via WorkingDirectory and set RUNNER_ROOT per-instance
# (see github-runner/default.nix). Re-derive defaults so the script also
# works if invoked manually.
: "${RUNNER_ROOT:=${HOME}/.github-runner/${NAME}}"
export RUNNER_ROOT
mkdir -p "${RUNNER_ROOT}"
cd "${RUNNER_ROOT}"

# Drop stale registration state from a previous crashed invocation.
# config.sh refuses to re-register with "Cannot configure the runner
# because it is already configured" even when --replace is passed.
rm -f "${RUNNER_ROOT}/.runner" \
      "${RUNNER_ROOT}/.credentials" \
      "${RUNNER_ROOT}/.credentials_rsaparams"

if [[ ! -r "${PAT_FILE}" ]]; then
  echo "[github-runner-${NAME}] PAT file ${PAT_FILE} not readable. Aborting." >&2
  sleep 30
  exit 1
fi
PAT="$(cat "${PAT_FILE}")"

# org URL: https://github.com/<org>     → orgs/<org>/actions/runners/registration-token
# repo URL: https://github.com/<o>/<r>  → repos/<o>/<r>/actions/runners/registration-token
PATH_PART="${URL#https://github.com/}"
PATH_PART="${PATH_PART%/}"
if [[ "${PATH_PART}" == */* ]]; then
  API="repos/${PATH_PART}/actions/runners/registration-token"
else
  API="orgs/${PATH_PART}/actions/runners/registration-token"
fi

echo "[github-runner-${NAME}] Requesting registration token from ${API}"
TOKEN="$(
  curl -fsSL -X POST \
    -H "Authorization: token ${PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/${API}" \
  | jq -r .token
)"

if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "[github-runner-${NAME}] Failed to obtain registration token" >&2
  exit 1
fi

# `config.sh` and `run.sh` come from pkgs.github-runner via PATH.
HOST_SHORT="$(uname -n)"
HOST_SHORT="${HOST_SHORT%%.*}"

echo "[github-runner-${NAME}] Configuring runner"
# --disableupdate: the runner package lives in /nix/store (read-only), so
# self-update can't rewrite Runner.Listener / lib/. Without this flag, every
# job ends with a failed SelfUpdate-*.log, the listener exits with
# "terminated error", launchd restarts our wrapper, and we burn cycles
# re-registering. Pin the version via flake.lock instead.
config.sh \
  --url "${URL}" \
  --token "${TOKEN}" \
  --name "${NAME}-${HOST_SHORT}" \
  --labels "${LABELS}" \
  --work _work \
  --ephemeral \
  --unattended \
  --replace \
  --disableupdate

echo "[github-runner-${NAME}] Listening for one job"
exec run.sh
