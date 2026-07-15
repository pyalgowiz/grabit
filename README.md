# Instagram Downloader Telegram Bot

A Telegram bot that allows users to download Instagram posts (photos, videos, carousels, reels) directly through Telegram with SOCKS5 proxy support.

## Features

- 📥 Download Instagram posts, reels, and carousels
- 🤖 Telegram bot interface with proxy support
- 🔄 Support for multiple URLs at once
- 📎 Automatic file type detection (photos/videos)
- 📝 Extract and send post captions with metadata
- 🖼️ Download and send post thumbnails/covers
- 📊 Display post metadata (uploader, date, views, likes)
- 🧹 Automatic cleanup after sending files
- 🔒 SOCKS5 proxy support for all network requests

## Setup

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Configure Environment Variables

**Create and configure `.env` file:**

```env
# Proxy Configuration (Optional - uncomment to enable)
# PROXY_HOST=127.0.0.1
# PROXY_PORT=12334

# Telegram Bot Configuration (Required)
TELEGRAM_BOT_TOKEN=your_actual_bot_token_here

# Instagram Credentials (Optional)
# Required for private posts and better rate limits
INSTAGRAM_USERNAME=your_instagram_username
INSTAGRAM_PASSWORD=your_instagram_password
```

### 3. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot` and follow the instructions
3. Copy your bot token and add it to `TELEGRAM_BOT_TOKEN` in `.env`

### 4. Configure SOCKS5 Proxy

Make sure your SOCKS5 proxy is running on the configured host and port (default: `127.0.0.1:12334`). All network requests (Instagram, Telegram, thumbnails) will use this proxy.

**Alternative configuration methods:**
- Environment variables: `export PROXY_HOST=your_host && export PROXY_PORT=your_port`
- Or run the bot and proxy will use defaults if not specified

### 4. Run the Bot

```bash
python tg_bot.py
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
1. **Thumbnail/Cover** - sent as a downloadable file (not compressed)
2. **Media file** - the actual photo/video content with embedded caption containing:
   - Post metadata (uploader, upload date, view/like counts)
   - Full text caption of the post

## Files

- `tg_bot.py` - Main Telegram bot script with proxy support
- `ig_loader.py` - Instagram downloader using instaloader + yt-dlp fallback
- `proxy.py` - Centralized SOCKS5 proxy configuration
- `test_carousel_bot.py` - Test script for carousel downloads
- `requirements.txt` - Python dependencies
- `.env` - Environment variables configuration
- `downloads/` - Directory where files are temporarily stored (auto-created)

## SOCKS5 Proxy Configuration (Optional)

The bot can optionally use a SOCKS5 proxy for all network requests to avoid rate limiting and IP blocks. If proxy settings are not configured in `.env`, the bot will operate without a proxy.

**Proxy usage:**
- **Instagram API requests** - Through instaloader library
- **Telegram API calls** - Through python-telegram-bot library
- **Thumbnail downloads** - Through requests library
- **Fallback downloads** - Through yt-dlp library

**To enable proxy, configure in `.env`:**
```env
PROXY_HOST=127.0.0.1
PROXY_PORT=12334
```

**To disable proxy, comment out or remove the proxy lines in `.env`**

## Notes

- Only public Instagram posts can be downloaded
- Files are automatically deleted after being sent
- The bot supports photos, videos, and carousel posts
- Multiple URLs can be sent in a single message
- Captions longer than 1000 characters are truncated
- SOCKS5 proxy is required for reliable operation

## Troubleshooting

- **Bot not responding**: Make sure your bot token is correct in `.env`
- **Download failures**: Check that the Instagram posts are public and accessible
- **Proxy errors**: Ensure your SOCKS5 proxy is running and configured correctly
- **Connection timeouts**: Verify proxy settings (if enabled) and network connectivity
- **Private accounts**: The bot cannot access private Instagram accounts
- **Rate limiting**: Instagram may block requests; proxy (if enabled) helps but isn't foolproof
