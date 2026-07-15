#!/usr/bin/env bash
#
# Instagram Telegram Bot — management script
#
# Usage:
#   ./bot.sh start          Run bot in background
#   ./bot.sh stop           Stop background bot
#   ./bot.sh restart        Restart bot
#   ./bot.sh status         Show running state
#   ./bot.sh logs           Show recent logs
#   ./bot.sh logs -f        Follow logs
#   ./bot.sh run            Run in foreground (debug)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-${SCRIPT_DIR}}"
PID_FILE="${APP_DIR}/.bot.pid"
LOG_FILE="${APP_DIR}/bot.log"
BOT_SCRIPT="${APP_DIR}/tg_bot.py"
VENV_PYTHON="${APP_DIR}/.venv/bin/python"

log() { printf '[bot] %s\n' "$*"; }
warn() { printf '[bot] WARNING: %s\n' "$*" >&2; }
die() { printf '[bot] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

resolve_python() {
  if [[ -x "${VENV_PYTHON}" ]]; then
    echo "${VENV_PYTHON}"
  elif command -v python3 >/dev/null 2>&1; then
    echo "python3"
  elif command -v python >/dev/null 2>&1; then
    echo "python"
  else
    die "Python not found. Run install.sh or create a virtualenv in ${APP_DIR}/.venv"
  fi
}

load_env() {
  if [[ -f "${APP_DIR}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${APP_DIR}/.env"
    set +a
  fi
}

validate_config() {
  [[ -f "${BOT_SCRIPT}" ]] || die "Bot script not found: ${BOT_SCRIPT}"

  load_env

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || "${TELEGRAM_BOT_TOKEN}" == "your_telegram_bot_token_here" ]]; then
    die "TELEGRAM_BOT_TOKEN is not set. Edit ${APP_DIR}/.env first."
  fi
}

is_running() {
  local pid="$1"
  kill -0 "${pid}" 2>/dev/null
}

read_pid() {
  if [[ -f "${PID_FILE}" ]]; then
    cat "${PID_FILE}"
  fi
}

get_running_pid() {
  local pid
  pid="$(read_pid || true)"
  if [[ -n "${pid}" ]] && is_running "${pid}"; then
    echo "${pid}"
    return 0
  fi
  return 1
}

cleanup_stale_pid() {
  local pid
  pid="$(read_pid || true)"
  if [[ -n "${pid}" ]] && ! is_running "${pid}"; then
    rm -f "${PID_FILE}"
  fi
}

cmd_start() {
  validate_config
  cleanup_stale_pid

  if pid="$(get_running_pid)"; then
    log "Bot is already running (PID ${pid})"
    exit 0
  fi

  local python_bin
  python_bin="$(resolve_python)"
  mkdir -p "${APP_DIR}/downloads"

  log "Starting bot in background..."
  log "App dir : ${APP_DIR}"
  log "Log file: ${LOG_FILE}"

  cd "${APP_DIR}"
  nohup "${python_bin}" "${BOT_SCRIPT}" >> "${LOG_FILE}" 2>&1 &
  echo "$!" > "${PID_FILE}"

  sleep 1
  if pid="$(get_running_pid)"; then
    log "Bot started (PID ${pid})"
  else
    rm -f "${PID_FILE}"
    die "Bot failed to start. Check ${LOG_FILE}"
  fi
}

cmd_stop() {
  cleanup_stale_pid

  local pid
  if ! pid="$(get_running_pid)"; then
    log "Bot is not running"
    rm -f "${PID_FILE}"
    exit 0
  fi

  log "Stopping bot (PID ${pid})..."
  kill "${pid}" 2>/dev/null || true

  for _ in $(seq 1 10); do
    if ! is_running "${pid}"; then
      rm -f "${PID_FILE}"
      log "Bot stopped"
      return 0
    fi
    sleep 1
  done

  warn "Bot did not stop gracefully, sending SIGKILL..."
  kill -9 "${pid}" 2>/dev/null || true
  rm -f "${PID_FILE}"
  log "Bot stopped"
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_status() {
  cleanup_stale_pid

  if pid="$(get_running_pid)"; then
    log "Bot is running (PID ${pid})"
    if command -v ps >/dev/null 2>&1; then
      ps -p "${pid}" -o pid=,etime=,cmd= 2>/dev/null || true
    fi
    exit 0
  fi

  log "Bot is not running"
  exit 1
}

cmd_logs() {
  [[ -f "${LOG_FILE}" ]] || die "Log file not found: ${LOG_FILE}"

  if [[ "${1:-}" == "-f" ]]; then
    tail -f "${LOG_FILE}"
  else
    tail -n 100 "${LOG_FILE}"
  fi
}

cmd_run() {
  validate_config

  local python_bin
  python_bin="$(resolve_python)"
  mkdir -p "${APP_DIR}/downloads"

  log "Running bot in foreground (Ctrl+C to stop)..."
  cd "${APP_DIR}"
  exec "${python_bin}" "${BOT_SCRIPT}"
}

main() {
  local command="${1:-}"
  shift || true

  case "${command}" in
    start)
      cmd_start
      ;;
    stop)
      cmd_stop
      ;;
    restart)
      cmd_restart
      ;;
    status)
      cmd_status
      ;;
    logs)
      cmd_logs "$@"
      ;;
    run|foreground|fg)
      cmd_run
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      die "Unknown command: ${command} (use --help)"
      ;;
  esac
}

main "$@"
