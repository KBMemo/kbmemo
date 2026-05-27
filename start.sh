#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${APP_ROOT}"

# 共通 PATH（rbenv / nvm より前に置く。後から prepend すると shims を上書きする）
export PATH="${HOME}/bin:/usr/local/Modules/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:${PATH:-}"

if [[ -d /usr/lib/jvm/java-21-openjdk-amd64/bin ]]; then
  export PATH="/usr/lib/jvm/java-21-openjdk-amd64/bin:${PATH}"
fi

# rbenv（shims / bin を PATH 先頭へ）
export RBENV_ROOT="${HOME}/.rbenv"
if [[ -d "${RBENV_ROOT}/bin" ]]; then
  export PATH="${RBENV_ROOT}/bin:${PATH}"
  eval "$(rbenv init - bash)"
fi

# nvm（ExecJS fallback, npm tooling）
export NVM_DIR="${HOME}/.nvm"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  source "${NVM_DIR}/nvm.sh"
  nvm use default >/dev/null 2>&1 || true
fi

ENV_FILE="${APP_ROOT}/.env.production"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE}" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

export RAILS_ENV="${RAILS_ENV:-production}"

exec bundle exec thrust ./bin/rails server
