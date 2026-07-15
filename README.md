# Instagram Downloader Telegram Bot

A Telegram bot that allows users to download Instagram posts (photos, videos, carousels, reels) directly through Telegram with SOCKS5 proxy support.

## Features

- Download Instagram posts, reels, and carousels
- Telegram bot interface with proxy support
- Support for multiple URLs at once
- Automatic file type detection (photos/videos)
- Extract and send post captions with metadata
- Download and send post thumbnails/covers
- Display post metadata (uploader, date, views, likes)
- Automatic cleanup after sending files
- SOCKS5 proxy support for all network requests

## Quick Install (Ubuntu Server)

One command — installs dependencies, clones the repo, configures the bot, and starts it:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/pyalgowiz/grabit/main/install.sh)
```

The installer will ask for:
1. **Telegram Bot Token** (required) — get it from [@BotFather](https://t.me/botfather)
2. **SOCKS5 proxy** (optional)
3. **Instagram credentials** (optional)

### Non-interactive install

```bash
TELEGRAM_BOT_TOKEN=your_bot_token bash <(curl -Ls https://raw.githubusercontent.com/pyalgowiz/grabit/main/install.sh)
```

With optional proxy:

```bash
TELEGRAM_BOT_TOKEN=your_token \
PROXY_HOST=127.0.0.1 \
PROXY_PORT=12334 \
bash <(curl -Ls https://raw.githubusercontent.com/pyalgowiz/grabit/main/install.sh)
```

### After install

The bot is installed to `/opt/grabit` and started automatically as a systemd service.

```bash
# Check status
systemctl status grabit

# View logs
journalctl -u grabit -f

# Restart
systemctl restart grabit
```

Or use the management script:

```bash
/opt/grabit/bot.sh status
/opt/grabit/bot.sh restart
/opt/grabit/bot.sh logs -f
```

## Manual Setup (Development)

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Configure Environment Variables

Copy `.env.example` to `.env` and edit:

```env
# Proxy Configuration (Optional)
PROXY_HOST=
PROXY_PORT=

# Telegram Bot Configuration (Required)
TELEGRAM_BOT_TOKEN=your_actual_bot_token_here

# Instagram Credentials (Optional)
INSTAGRAM_USERNAME=
INSTAGRAM_PASSWORD=

# Paths (Optional)
DOWNLOAD_DIR=downloads
INSTAGRAM_SESSION_FILE=instagram_session
```

### 3. Run the Bot

Foreground:

```bash
python tg_bot.py
```

Background:

```bash
./bot.sh start
./bot.sh status
./bot.sh logs -f
```

## Usage

1. Start a chat with your bot on Telegram
2. Send `/start` to see the welcome message
3. Send Instagram URLs (one or multiple per message)
4. Wait for the bot to download and send back the files

### Supported URL Formats

- Posts: `https://www.instagram.com/p/...`
- Reels: `https://www.instagram.com/reel/...`
- Stories: `https://www.instagram.com/stories/...`

## What You Get

For each Instagram post, the bot will send you:
1. **Thumbnail/Cover** — sent as a downloadable file (not compressed)
2. **Media file** — the actual photo/video content with embedded caption containing:
   - Post metadata (uploader, upload date, view/like counts)
   - Full text caption of the post

## Files

- `tg_bot.py` — Main Telegram bot script
- `ig_loader.py` — Instagram downloader using instaloader + yt-dlp fallback
- `proxy.py` — Centralized SOCKS5 proxy configuration
- `install.sh` — One-click Ubuntu server installer
- `bot.sh` — Bot management script (start/stop/restart/logs)
- `requirements.txt` — Python dependencies
- `.env.example` — Environment variables template
- `downloads/` — Temporary download directory (auto-created)

## SOCKS5 Proxy Configuration (Optional)

The bot can optionally use a SOCKS5 proxy for all network requests. If proxy settings are not configured, the bot runs without a proxy.

**Proxy usage:**
- Instagram API requests — through instaloader
- Telegram API calls — through python-telegram-bot
- Thumbnail downloads — through requests
- Fallback downloads — through yt-dlp

**To enable proxy in `.env`:**
```env
PROXY_HOST=127.0.0.1
PROXY_PORT=12334
```

## Troubleshooting

- **Bot not responding**: Check `TELEGRAM_BOT_TOKEN` in `/opt/grabit/.env`
- **Service not running**: `systemctl status grabit` and `journalctl -u grabit -n 50`
- **Download failures**: Ensure Instagram posts are public and accessible
- **Proxy errors**: Verify SOCKS5 proxy is running and configured correctly
- **Private accounts**: The bot cannot access private Instagram accounts without valid Instagram credentials
- **Rate limiting**: Instagram may block requests; a proxy helps but is not foolproof

## Update

```bash
bash <(curl -Ls https://raw.githubusercontent.com/pyalgowiz/grabit/main/install.sh) --update
```

Or:

```bash
cd /opt/grabit
git pull
source .venv/bin/activate && pip install -r requirements.txt
systemctl restart grabit
```
