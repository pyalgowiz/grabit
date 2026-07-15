#!/usr/bin/env bash
#
# Instagram Telegram Bot — server install script
#
# Install from GitHub (one-liner):
#   GITHUB_REPO=your-user/your-repo curl -fsSL \
#     "https://raw.githubusercontent.com/your-user/your-repo/main/install.sh" | sudo bash
#
# Or clone first, then run locally:
#   git clone "https://github.com/your-user/your-repo.git"
#   cd your-repo && sudo ./install.sh
#
# Options:
#   --repo USER/REPO     GitHub repository (owner/name)
#   --branch BRANCH      Git branch to install (default: main)
#   --dir PATH           Install directory (default: /opt/instagram-telegram-bot)
#   --token TOKEN        Telegram bot token (skips interactive prompt)
#   --user NAME          System user to run the bot (default: igbot)
#   --no-systemd         Skip systemd service setup
#   --update             Update an existing installation
#   -h, --help           Show help
#
set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/instagram-telegram-bot}"
SERVICE_NAME="${SERVICE_NAME:-instagram-telegram-bot}"
RUN_USER="${RUN_USER:-igbot}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
SKIP_SYSTEMD=0
UPDATE_MODE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SOURCE=0
if [[ -f "${SCRIPT_DIR}/tg_bot.py" && -f "${SCRIPT_DIR}/requirements.txt" ]]; then
  LOCAL_SOURCE=1
fi

log() { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARNING: %s\n' "$*" >&2; }
die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || die "--repo requires an argument (owner/name)"
        GITHUB_REPO="$2"
        shift 2
        ;;
      --branch)
        [[ $# -ge 2 ]] || die "--branch requires an argument"
        REPO_BRANCH="$2"
        shift 2
        ;;
      --dir)
        [[ $# -ge 2 ]] || die "--dir requires an argument"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --token)
        [[ $# -ge 2 ]] || die "--token requires an argument"
        TELEGRAM_BOT_TOKEN="$2"
        shift 2
        ;;
      --user)
        [[ $# -ge 2 ]] || die "--user requires an argument"
        RUN_USER="$2"
        shift 2
        ;;
      --no-systemd)
        SKIP_SYSTEMD=1
        shift
        ;;
      --update)
        UPDATE_MODE=1
        shift
        ;;
      -h|--help)
        usage
        ;;
      *)
        die "Unknown option: $1 (use --help)"
        ;;
    esac
  done
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-}"
  else
    OS_ID="unknown"
  fi
}

install_system_packages() {
  log "Installing system dependencies..."
  case "${OS_ID}" in
    debian|ubuntu|raspbian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y --no-install-recommends \
        ca-certificates curl git python3 python3-pip python3-venv ffmpeg rsync
      ;;
    fedora)
      dnf install -y ca-certificates curl git python3 python3-pip ffmpeg
      ;;
    centos|rhel|rocky|almalinux)
      dnf install -y ca-certificates curl git python3 python3-pip ffmpeg || \
        yum install -y ca-certificates curl git python3 python3-pip ffmpeg
      ;;
    alpine)
      apk add --no-cache ca-certificates curl git python3 py3-pip ffmpeg
      ;;
    *)
      warn "Unsupported OS '${OS_ID}'. Ensure python3, python3-venv, git, and curl are installed."
      command -v python3 >/dev/null 2>&1 || die "python3 is required but not found."
      command -v git >/dev/null 2>&1 || die "git is required but not found."
      ;;
  esac
}

resolve_repo_url() {
  if [[ -n "${GITHUB_REPO}" ]]; then
    REPO_URL="https://github.com/${GITHUB_REPO}.git"
    return
  fi

  if [[ "${LOCAL_SOURCE}" -eq 1 ]]; then
    if git -C "${SCRIPT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      remote="$(git -C "${SCRIPT_DIR}" remote get-url origin 2>/dev/null || true)"
      if [[ -n "${remote}" ]]; then
        REPO_URL="${remote}"
        log "Detected repository from git remote: ${REPO_URL}"
        return
      fi
    fi
  fi

  die "GitHub repository not specified. Set GITHUB_REPO=owner/repo, use --repo owner/repo, or run from a cloned repository."
}

sync_source() {
  resolve_repo_url

  if [[ "${LOCAL_SOURCE}" -eq 1 && "${SCRIPT_DIR}" == "${INSTALL_DIR}" ]]; then
    log "Installing from current directory: ${INSTALL_DIR}"
    return
  fi

  if [[ "${LOCAL_SOURCE}" -eq 1 && "${UPDATE_MODE}" -eq 0 ]]; then
    log "Copying local source to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude '.git' \
        --exclude '.venv' \
        --exclude 'venv' \
        --exclude '__pycache__' \
        --exclude '.env' \
        --exclude 'downloads' \
        --exclude 'instagram_session' \
        --exclude 'instagram_session*' \
        --exclude '*.log' \
        --exclude '.history' \
        "${SCRIPT_DIR}/" "${INSTALL_DIR}/"
    else
      find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 \
        ! -name '.env' ! -name 'downloads' ! -name '.venv' \
        -exec rm -rf {} +
      tar -C "${SCRIPT_DIR}" \
        --exclude='.git' --exclude='.venv' --exclude='venv' \
        --exclude='__pycache__' --exclude='.env' --exclude='downloads' \
        --exclude='instagram_session' --exclude='instagram_session*' \
        --exclude='*.log' --exclude='.history' \
        -cf - . | tar -C "${INSTALL_DIR}" -xf -
    fi
    return
  fi

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log "Updating existing clone in ${INSTALL_DIR}..."
    git -C "${INSTALL_DIR}" fetch origin
    git -C "${INSTALL_DIR}" checkout "${REPO_BRANCH}"
    git -C "${INSTALL_DIR}" pull --ff-only origin "${REPO_BRANCH}"
  else
    log "Cloning ${REPO_URL} (branch: ${REPO_BRANCH}) into ${INSTALL_DIR}..."
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
  fi
}

ensure_run_user() {
  if id "${RUN_USER}" >/dev/null 2>&1; then
    log "Using existing user: ${RUN_USER}"
  else
    log "Creating system user: ${RUN_USER}"
    useradd --system --home-dir "${INSTALL_DIR}" --shell /usr/sbin/nologin "${RUN_USER}" 2>/dev/null || \
      useradd --system --home-dir "${INSTALL_DIR}" --shell /bin/false "${RUN_USER}"
  fi
}

setup_python_env() {
  log "Setting up Python virtual environment..."
  cd "${INSTALL_DIR}"

  if [[ ! -d ".venv" ]]; then
    python3 -m venv .venv
  fi

  # shellcheck disable=SC1091
  source .venv/bin/activate
  python -m pip install --upgrade pip wheel
  python -m pip install -r requirements.txt
  deactivate
}

setup_env_file() {
  local env_file="${INSTALL_DIR}/.env"

  if [[ ! -f "${env_file}" ]]; then
    if [[ -f "${INSTALL_DIR}/.env.example" ]]; then
      cp "${INSTALL_DIR}/.env.example" "${env_file}"
      log "Created ${env_file} from .env.example"
    else
      die ".env.example not found in ${INSTALL_DIR}"
    fi
  else
    log "Keeping existing ${env_file}"
  fi

  if [[ -n "${TELEGRAM_BOT_TOKEN}" ]]; then
    if grep -q '^TELEGRAM_BOT_TOKEN=' "${env_file}"; then
      sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" "${env_file}"
    else
      printf '\nTELEGRAM_BOT_TOKEN=%s\n' "${TELEGRAM_BOT_TOKEN}" >> "${env_file}"
    fi
    log "Telegram bot token configured"
  elif grep -qE '^TELEGRAM_BOT_TOKEN=(your_telegram_bot_token_here)?$' "${env_file}" 2>/dev/null || \
       ! grep -q '^TELEGRAM_BOT_TOKEN=.\+' "${env_file}" 2>/dev/null; then
    warn "TELEGRAM_BOT_TOKEN is not set in ${env_file}"
    warn "Edit the file and set your token from @BotFather, then restart the service."
  fi
}

setup_directories() {
  mkdir -p "${INSTALL_DIR}/downloads"
  chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}"
  chmod 750 "${INSTALL_DIR}"
  chmod 600 "${INSTALL_DIR}/.env" 2>/dev/null || true
}

install_systemd_service() {
  [[ "${SKIP_SYSTEMD}" -eq 0 ]] || return 0

  local unit_file="/etc/systemd/system/${SERVICE_NAME}.service"

  log "Installing systemd service: ${SERVICE_NAME}"
  cat > "${unit_file}" <<EOF
[Unit]
Description=Instagram Telegram Bot
Documentation=https://github.com/${GITHUB_REPO:-your-user/your-repo}
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

  if grep -qE '^TELEGRAM_BOT_TOKEN=.+$' "${INSTALL_DIR}/.env" && \
     ! grep -q '^TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here$' "${INSTALL_DIR}/.env"; then
    systemctl restart "${SERVICE_NAME}.service"
    log "Service started: ${SERVICE_NAME}"
  else
    warn "Service enabled but not started — configure TELEGRAM_BOT_TOKEN in ${INSTALL_DIR}/.env first."
    warn "Then run: systemctl start ${SERVICE_NAME}"
  fi
}

print_summary() {
  cat <<EOF

Installation complete.

  Install dir : ${INSTALL_DIR}
  Service     : ${SERVICE_NAME}
  Run user    : ${RUN_USER}
  Config file : ${INSTALL_DIR}/.env

Next steps:
  1. Edit ${INSTALL_DIR}/.env and set TELEGRAM_BOT_TOKEN (and optional proxy/Instagram credentials)
  2. Start or restart the bot:
       systemctl start ${SERVICE_NAME}
       systemctl restart ${SERVICE_NAME}
  3. Check logs:
       journalctl -u ${SERVICE_NAME} -f

Manual run (without systemd):
  cd ${INSTALL_DIR}
  source .venv/bin/activate
  python tg_bot.py

EOF
}

main() {
  parse_args "$@"
  require_root
  detect_os
  install_system_packages
  sync_source
  ensure_run_user
  setup_python_env
  setup_env_file
  setup_directories
  install_systemd_service
  print_summary
}

main "$@"
