#!/usr/bin/env bash
#
# Instagram Telegram Bot — one-click server installer
#
# Ubuntu (recommended):
#   bash <(curl -Ls https://raw.githubusercontent.com/pyalgowiz/grabit/main/install.sh)
#
# With token (non-interactive):
#   TELEGRAM_BOT_TOKEN=your_token bash <(curl -Ls https://raw.githubusercontent.com/pyalgowiz/grabit/main/install.sh)
#
set -euo pipefail

# --- defaults (override with env vars or CLI flags) ---
GITHUB_REPO="${GITHUB_REPO:-pyalgowiz/grabit}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/grabit}"
SERVICE_NAME="${SERVICE_NAME:-grabit}"
RUN_USER="${RUN_USER:-grabit}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
PROXY_HOST="${PROXY_HOST:-}"
PROXY_PORT="${PROXY_PORT:-}"
INSTAGRAM_USERNAME="${INSTAGRAM_USERNAME:-}"
INSTAGRAM_PASSWORD="${INSTAGRAM_PASSWORD:-}"
SKIP_SYSTEMD=0
UPDATE_MODE=0

# --- colors ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SOURCE=0
if [[ -f "${SCRIPT_DIR}/tg_bot.py" && -f "${SCRIPT_DIR}/requirements.txt" ]]; then
  LOCAL_SOURCE=1
fi

if [[ "${NONINTERACTIVE:-0}" == "1" ]] || [[ ! -t 0 ]]; then
  NONINTERACTIVE=1
else
  NONINTERACTIVE=0
fi

log()  { echo -e "${green}[+]${plain} $*"; }
warn() { echo -e "${yellow}[!]${plain} $*" >&2; }
err()  { echo -e "${red}[x]${plain} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<EOF
Instagram Telegram Bot installer

Usage:
  bash <(curl -Ls https://raw.githubusercontent.com/${GITHUB_REPO}/${REPO_BRANCH}/install.sh)

Options:
  --repo USER/REPO       GitHub repository (default: ${GITHUB_REPO})
  --branch BRANCH        Git branch (default: ${REPO_BRANCH})
  --dir PATH             Install directory (default: ${INSTALL_DIR})
  --token TOKEN          Telegram bot token
  --proxy-host HOST      SOCKS5 proxy host (optional)
  --proxy-port PORT      SOCKS5 proxy port (optional)
  --ig-user USER         Instagram username (optional)
  --ig-pass PASS         Instagram password (optional)
  --no-systemd           Skip systemd service setup
  --update               Update existing installation
  -h, --help             Show this help

Environment:
  TELEGRAM_BOT_TOKEN, PROXY_HOST, PROXY_PORT,
  INSTAGRAM_USERNAME, INSTAGRAM_PASSWORD, NONINTERACTIVE=1
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)        GITHUB_REPO="$2"; shift 2 ;;
      --branch)      REPO_BRANCH="$2"; shift 2 ;;
      --dir)         INSTALL_DIR="$2"; shift 2 ;;
      --token)       TELEGRAM_BOT_TOKEN="$2"; shift 2 ;;
      --proxy-host)  PROXY_HOST="$2"; shift 2 ;;
      --proxy-port)  PROXY_PORT="$2"; shift 2 ;;
      --ig-user)     INSTAGRAM_USERNAME="$2"; shift 2 ;;
      --ig-pass)     INSTAGRAM_PASSWORD="$2"; shift 2 ;;
      --no-systemd)  SKIP_SYSTEMD=1; shift ;;
      --update)      UPDATE_MODE=1; shift ;;
      -h|--help)     usage ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
  done
}

prompt_or_default() {
  local __var="$1" __prompt="$2" __default="$3" __env="${4:-$1}"
  if [[ "${NONINTERACTIVE}" -eq 1 ]]; then
    printf -v "$__var" '%s' "${!__env:-$__default}"
    return
  fi
  if [[ -n "$__default" ]]; then
    read -rp "$(echo -e "${blue}${__prompt}${plain} [${__default}]: ")" "$__var"
    [[ -z "${!__var}" ]] && printf -v "$__var" '%s' "$__default"
  else
    read -rp "$(echo -e "${blue}${__prompt}${plain}: ")" "$__var"
  fi
}

prompt_secret() {
  local __var="$1" __prompt="$2" __env="${3:-$1}"
  if [[ "${NONINTERACTIVE}" -eq 1 ]]; then
    printf -v "$__var" '%s' "${!__env:-}"
    return
  fi
  read -rsp "$(echo -e "${blue}${__prompt}${plain}: ")" "$__var"
  echo
}

show_banner() {
  clear || true
  echo -e "${green}"
  cat <<'EOF'
  ____       _      _ _   
 / ___| __ _| | ___| | |__
| |  _ / _` | |/ _ \ | '_ \
| |_| | (_| | |  __/ | |_) |
 \____|\__,_|_|\___|_|_.__/

 Instagram Downloader Telegram Bot
EOF
  echo -e "${plain}"
  echo -e "Repository : ${blue}https://github.com/${GITHUB_REPO}${plain}"
  echo -e "Install to : ${blue}${INSTALL_DIR}${plain}"
  echo
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run as root: sudo bash <(curl -Ls ...)"
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
  else
    OS_ID="unknown"
  fi

  case "${OS_ID}" in
    ubuntu|debian|raspbian) ;;
    *)
      warn "This installer is optimized for Ubuntu/Debian. Detected: ${OS_ID}"
      ;;
  esac
}

install_system_packages() {
  log "Installing system packages..."
  case "${OS_ID}" in
    debian|ubuntu|raspbian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y --no-install-recommends \
        ca-certificates curl git python3 python3-pip python3-venv ffmpeg rsync
      ;;
    fedora)
      dnf install -y ca-certificates curl git python3 python3-pip ffmpeg rsync
      ;;
    centos|rhel|rocky|almalinux)
      dnf install -y ca-certificates curl git python3 python3-pip ffmpeg rsync || \
        yum install -y ca-certificates curl git python3 python3-pip ffmpeg rsync
      ;;
    alpine)
      apk add --no-cache ca-certificates curl git python3 py3-pip ffmpeg rsync
      ;;
    *)
      command -v python3 >/dev/null 2>&1 || die "python3 is required."
      command -v git >/dev/null 2>&1 || die "git is required."
      ;;
  esac
}

sync_source() {
  REPO_URL="https://github.com/${GITHUB_REPO}.git"

  if [[ "${LOCAL_SOURCE}" -eq 1 && "${SCRIPT_DIR}" == "${INSTALL_DIR}" ]]; then
    log "Using current directory as install source."
    return
  fi

  if [[ "${LOCAL_SOURCE}" -eq 1 && "${UPDATE_MODE}" -eq 0 ]]; then
    log "Copying local source to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude '.git' --exclude '.venv' --exclude 'venv' \
        --exclude '__pycache__' --exclude '.env' --exclude 'downloads' \
        --exclude 'instagram_session' --exclude 'instagram_session*' \
        --exclude '*.log' --exclude '.history' --exclude '.bot.pid' \
        "${SCRIPT_DIR}/" "${INSTALL_DIR}/"
    else
      tar -C "${SCRIPT_DIR}" \
        --exclude='.git' --exclude='.venv' --exclude='.env' \
        --exclude='downloads' --exclude='*.log' --exclude='.history' \
        -cf - . | tar -C "${INSTALL_DIR}" -xf -
    fi
    return
  fi

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log "Updating existing installation..."
    git -C "${INSTALL_DIR}" fetch origin
    git -C "${INSTALL_DIR}" checkout "${REPO_BRANCH}"
    git -C "${INSTALL_DIR}" pull --ff-only origin "${REPO_BRANCH}"
  else
    log "Cloning ${REPO_URL}..."
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
  fi
}

ensure_run_user() {
  if id "${RUN_USER}" >/dev/null 2>&1; then
    log "Using system user: ${RUN_USER}"
  else
    log "Creating system user: ${RUN_USER}"
    useradd --system --home-dir "${INSTALL_DIR}" --shell /usr/sbin/nologin "${RUN_USER}" 2>/dev/null || \
      useradd --system --home-dir "${INSTALL_DIR}" --shell /bin/false "${RUN_USER}"
  fi
}

setup_python_env() {
  log "Setting up Python environment..."
  cd "${INSTALL_DIR}"

  [[ -d ".venv" ]] || python3 -m venv .venv

  # shellcheck disable=SC1091
  source .venv/bin/activate
  python -m pip install --upgrade pip wheel -q
  python -m pip install -r requirements.txt -q
  deactivate
}

collect_config() {
  local env_file="${INSTALL_DIR}/.env"

  if [[ "${UPDATE_MODE}" -eq 1 && -f "${env_file}" && -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    log "Update mode: keeping existing ${env_file}"
    # shellcheck disable=SC1091
    source "${env_file}"
    TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
    return
  fi

  echo
  echo -e "${green}=== Configuration ===${plain}"
  echo -e "Get a bot token from ${blue}@BotFather${plain} on Telegram."
  echo

  if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
    if [[ "${NONINTERACTIVE}" -eq 1 ]]; then
      die "TELEGRAM_BOT_TOKEN is required in non-interactive mode."
    fi
    while [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; do
      prompt_secret TELEGRAM_BOT_TOKEN "Enter Telegram Bot Token" TELEGRAM_BOT_TOKEN
      [[ -n "${TELEGRAM_BOT_TOKEN}" ]] || err "Bot token is required."
    done
  fi

  if [[ "${NONINTERACTIVE}" -eq 0 ]]; then
    echo
    echo -e "${yellow}Optional: SOCKS5 proxy (press Enter to skip)${plain}"
    prompt_or_default PROXY_HOST "Proxy host" "" PROXY_HOST
    if [[ -n "${PROXY_HOST}" ]]; then
      prompt_or_default PROXY_PORT "Proxy port" "12334" PROXY_PORT
    fi

    echo
    echo -e "${yellow}Optional: Instagram credentials (press Enter to skip)${plain}"
    prompt_or_default INSTAGRAM_USERNAME "Instagram username" "" INSTAGRAM_USERNAME
    if [[ -n "${INSTAGRAM_USERNAME}" ]]; then
      prompt_secret INSTAGRAM_PASSWORD "Instagram password" INSTAGRAM_PASSWORD
    fi
  fi
}

write_env_file() {
  local env_file="${INSTALL_DIR}/.env"

  if [[ "${UPDATE_MODE}" -eq 1 && -f "${env_file}" && -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    return
  fi

  log "Writing ${env_file}..."

  cat > "${env_file}" <<EOF
# Generated by install.sh on $(date -u +"%Y-%m-%d %H:%M:%S UTC")

PROXY_HOST=${PROXY_HOST}
PROXY_PORT=${PROXY_PORT}

TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}

INSTAGRAM_USERNAME=${INSTAGRAM_USERNAME}
INSTAGRAM_PASSWORD=${INSTAGRAM_PASSWORD}

DOWNLOAD_DIR=downloads
INSTAGRAM_SESSION_FILE=instagram_session
EOF

  chmod 600 "${env_file}"
}

setup_directories() {
  mkdir -p "${INSTALL_DIR}/downloads"
  chmod +x "${INSTALL_DIR}/bot.sh" 2>/dev/null || true
  chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}"
  chmod 750 "${INSTALL_DIR}"
}

install_systemd_service() {
  [[ "${SKIP_SYSTEMD}" -eq 0 ]] || return 0

  local unit_file="/etc/systemd/system/${SERVICE_NAME}.service"
  log "Installing systemd service: ${SERVICE_NAME}"

  cat > "${unit_file}" <<EOF
[Unit]
Description=Instagram Telegram Bot (grabit)
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${INSTALL_DIR}/.venv/bin/python ${INSTALL_DIR}/tg_bot.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
}

start_bot() {
  log "Starting bot..."

  if [[ "${SKIP_SYSTEMD}" -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl restart "${SERVICE_NAME}.service"
    sleep 2
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
      log "Bot is running via systemd (${SERVICE_NAME})"
      return 0
    fi
    warn "systemd start failed, trying bot.sh..."
    journalctl -u "${SERVICE_NAME}" -n 20 --no-pager 2>/dev/null || true
  fi

  if [[ -x "${INSTALL_DIR}/bot.sh" ]]; then
    cd "${INSTALL_DIR}"
    sudo -u "${RUN_USER}" APP_DIR="${INSTALL_DIR}" ./bot.sh start
    log "Bot is running via bot.sh"
    return 0
  fi

  die "Failed to start the bot. Check logs in ${INSTALL_DIR}/bot.log"
}

print_summary() {
  echo
  echo -e "${green}================================${plain}"
  echo -e "${green}  Installation completed!${plain}"
  echo -e "${green}================================${plain}"
  echo
  echo -e "Install dir : ${blue}${INSTALL_DIR}${plain}"
  echo -e "Service     : ${blue}${SERVICE_NAME}${plain}"
  echo -e "Config      : ${blue}${INSTALL_DIR}/.env${plain}"
  echo
  echo -e "${green}Manage the bot:${plain}"
  echo -e "  systemctl status ${SERVICE_NAME}"
  echo -e "  systemctl restart ${SERVICE_NAME}"
  echo -e "  systemctl stop ${SERVICE_NAME}"
  echo -e "  journalctl -u ${SERVICE_NAME} -f"
  echo
  echo -e "  ${INSTALL_DIR}/bot.sh start"
  echo -e "  ${INSTALL_DIR}/bot.sh stop"
  echo -e "  ${INSTALL_DIR}/bot.sh status"
  echo -e "  ${INSTALL_DIR}/bot.sh logs -f"
  echo
  echo -e "${green}Usage:${plain} Open your bot in Telegram and send an Instagram post URL."
  echo
}

main() {
  parse_args "$@"
  show_banner
  require_root
  detect_os
  install_system_packages
  sync_source
  ensure_run_user
  setup_python_env
  collect_config
  write_env_file
  setup_directories
  install_systemd_service
  start_bot
  print_summary
}

main "$@"
