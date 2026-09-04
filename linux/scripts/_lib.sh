# shellcheck shell=bash
# Utilidades comunes. Se hace `source`, no se ejecuta.
# shellcheck disable=SC2034  # lo consumen los scripts que hacen source
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Docker Compose v2 (plugin) o v1 (binario suelto). En esta maquina, hoy, es v1.
compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "No hay ni 'docker compose' ni 'docker-compose'." >&2
    return 1
  fi
}

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
fail() { printf '  \033[31mFALLO\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m--\033[0m    %s\n' "$*"; }
