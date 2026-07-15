"""
Telegram Bot for Instagram Downloads
Install dependencies: pip install python-telegram-bot instaloader
"""

import asyncio
import os
import re
import requests
from io import BytesIO
from datetime import datetime
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.request import HTTPXRequest
from ig_loader import InstagramDownloader
from proxy import proxy_config
import jdatetime

class TelegramBot:
    def __init__(self, token, ig_username=None, ig_password=None, output_dir=None):
        self.token = token
        self.proxy_config = proxy_config

        if self.proxy_config.enabled:
            self.proxy_config.configure_socket_proxy()

        self.downloader = InstagramDownloader(
            output_dir=output_dir,
            username=ig_username,
            password=ig_password,
        )

    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Send welcome message"""
        welcome_text = f"""🤖 Instagram Downloader Bot

Send me Instagram post URLs and I'll download them for you!

Supported formats:
• Single posts (photos/videos)
• Carousel posts
• Reels
• Stories (if public)

Just paste the Instagram URL and wait for your download! 📥"""
        await update.message.reply_text(welcome_text)

    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Send help message"""
        help_text = """
📖 Help

How to use:
1. Copy an Instagram post URL
2. Send it to me
3. Wait for the download to complete
4. Receive your file!

Supported URLs:
• https://www.instagram.com/p/...
• https://www.instagram.com/reel/...
• https://www.instagram.com/stories/...

Note: Only public posts can be downloaded."""
        await update.message.reply_text(help_text)

    def extract_instagram_urls(self, text):
        """Extract Instagram URLs from text"""
        # Regex pattern for Instagram URLs
        instagram_pattern = r'https?://(?:www\.)?instagram\.com/(?:p|reel|stories)/[^/\s]+/?'
        urls = re.findall(instagram_pattern, text)
        return urls

    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle incoming messages"""
        message_text = update.message.text

        # Extract Instagram URLs from the message
        urls = self.extract_instagram_urls(message_text)

        if not urls:
            await update.message.reply_text(
                "❌ No Instagram URLs found in your message.\n\n"
                "Please send a valid Instagram post URL.\n"
                "Use /help for more information."
            )
            return

        await update.message.reply_text(f"🔄 Found {len(urls)} Instagram URL(s). Starting download...")

        downloaded_files = []

        for i, url in enumerate(urls, 1):
            try:
                await update.message.reply_text(f"📥 Downloading {i}/{len(urls)}: {url}", disable_web_page_preview=True)

                # Download the file using the existing downloader
                result = self.downloader.download(url)

                # Check if download was successful (handles both single posts and carousels)
                download_successful = False
                if result:
                    if result.get('is_carousel'):
                        # For carousel posts, check if filenames list exists and has valid files
                        download_successful = (result.get('filenames') and
                                             any(os.path.exists(f) for f in result['filenames']))
                    else:
                        # For single posts, check if filename exists
                        download_successful = (result.get('filename') and
                                             os.path.exists(result['filename']))

                if download_successful:
                    # Prepare combined caption for media (without caption text)
                    caption_parts = []

                    # Add post information
                    info_parts = []
                    if result.get('uploader'):
                        # Make uploader a clickable profile link
                        uploader_username = result['uploader']
                        profile_url = f"https://www.instagram.com/{uploader_username}/"
                        info_parts.append(f"👤 **Uploader:** [{uploader_username}]({profile_url})")
                    if result.get('upload_date'):
                        # Convert date to Jalali (Persian) calendar
                        upload_date = result['upload_date']
                        if len(upload_date) == 8:  # YYYYMMDD format
                            try:
                                # Parse Gregorian date
                                gregorian_date = datetime.strptime(upload_date, '%Y%m%d')
                                # Convert to Jalali
                                jalali_date = jdatetime.date.fromgregorian(date=gregorian_date.date())
                                formatted_date = jalali_date.strftime('%Y/%m/%d')
                                info_parts.append(f"📅 **Date:** {formatted_date}")
                            except Exception as e:
                                # Fallback to original format if conversion fails
                                formatted_date = f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:]}"
                                info_parts.append(f"📅 **Date:** {formatted_date}")
                    if result.get('view_count', 0) > 0:
                        info_parts.append(f"👁️ **Views:** {result['view_count']:,}")
                    if result.get('like_count', 0) > 0:
                        info_parts.append(f"❤️ **Likes:** {result['like_count']:,}")
                    if result.get('comment_count', 0) > 0:
                        info_parts.append(f"💬 **Comments:** {result['comment_count']:,}")

                    if info_parts:
                        caption_parts.append("📋 **Post Info:**\n" + "\n".join(info_parts))

                    # Combine all caption parts (without caption text)
                    full_caption = "\n\n".join(caption_parts) if caption_parts else None

                    # Store caption text separately for sending as another message
                    caption_text = None
                    if result.get('description') and result['description'].strip():
                        caption_text = result['description'][:1000]
                        if len(result['description']) > 1000:
                            caption_text += "..."

                    # Store the combined caption and separate caption text with the result
                    result['full_caption'] = full_caption
                    result['caption_text'] = caption_text
                    downloaded_files.append(result)

                    # Send thumbnail/cover image as document if available
                    if result.get('thumbnail'):
                        try:
                            # Download thumbnail
                            response = requests.get(result['thumbnail'], timeout=10)
                            if response.status_code == 200:
                                thumb_data = BytesIO(response.content)
                                thumb_data.seek(0)
                                await update.message.reply_document(
                                    document=thumb_data,
                                    filename="thumbnail.jpg",
                                    caption="🖼️ **Post Thumbnail/Cover**"
                                )
                        except Exception as thumb_error:
                            print(f"Failed to download thumbnail: {thumb_error}")
                            # Continue without thumbnail

                else:
                    await update.message.reply_text(f"❌ Failed to download: {url}")

            except Exception as e:
                await update.message.reply_text(f"❌ Error downloading {url}: {str(e)}")

        # Send downloaded files back to user
        for result in downloaded_files:
            try:
                if result.get('is_carousel'):
                    # Handle carousel posts (multiple images)
                    filenames = result.get('filenames', [])
                    if filenames:
                        # Send as media group for multiple images
                        from telegram import InputMediaPhoto

                        media_group = []
                        for i, file_path in enumerate(filenames):
                            if file_path.lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                                # Add caption only to the first image
                                if i == 0:
                                    media_group.append(InputMediaPhoto(
                                        media=open(file_path, 'rb'),
                                        caption=result.get('full_caption'),
                                        parse_mode='Markdown'
                                    ))
                                else:
                                    media_group.append(InputMediaPhoto(media=open(file_path, 'rb')))

                        if media_group:
                            await update.message.reply_media_group(media=media_group)

                        # Send caption text as separate message if available
                        if result.get('caption_text'):
                            await update.message.reply_text(f"📝 **Caption:**\n{result['caption_text']}", parse_mode='Markdown')

                        # Clean up all carousel files
                        for file_path in filenames:
                            try:
                                os.remove(file_path)
                            except:
                                pass
                    else:
                        await update.message.reply_text("❌ No carousel images found")
                else:
                    # Handle single posts (image or video)
                    file_path = result['filename']
                    # Determine file type and send accordingly
                    if file_path.lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                        # Send as photo with caption
                        await update.message.reply_photo(
                            photo=open(file_path, 'rb'),
                            caption=result.get('full_caption'),
                            parse_mode='Markdown'
                        )
                    elif file_path.lower().endswith(('.mp4', '.mov', '.avi', '.mkv')):
                        # Send as video with combined caption
                        await update.message.reply_video(
                            video=open(file_path, 'rb'),
                            caption=result.get('full_caption'),
                            parse_mode='Markdown'
                        )
                    else:
                        # Send as document for other file types
                        await update.message.reply_document(document=open(file_path, 'rb'))

                    # Send caption text as separate message if available
                    if result.get('caption_text'):
                        await update.message.reply_text(f"📝 **Caption:**\n{result['caption_text']}", parse_mode='Markdown')

                    # Clean up the file after sending
                    os.remove(file_path)

            except Exception as e:
                filename = result.get('filename') or result.get('filenames', ['unknown'])[0] if result.get('filenames') else 'unknown'
                await update.message.reply_text(f"❌ Error sending file {os.path.basename(filename)}: {str(e)}")

        if downloaded_files:
            await update.message.reply_text("✅ All downloads completed!")
        else:
            await update.message.reply_text("❌ No files were successfully downloaded.")

    def run(self):
        """Run the bot"""

        request = HTTPXRequest(**self.proxy_config.telegram)

        application = (
            Application.builder()
            .token(self.token)
            .request(request)
            .build()
        )

        # Add handlers
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))

        # Start the bot
        print("🤖 Bot is running... Press Ctrl+C to stop")
        application.run_polling()


def save_token_to_env(token):
    """Save bot token to .env file"""
    env_file = '.env'
    
    # Read existing .env file
    env_lines = []
    token_found = False
    
    if os.path.exists(env_file):
        with open(env_file, 'r', encoding='utf-8') as f:
            env_lines = f.readlines()
    
    # Update or add TELEGRAM_BOT_TOKEN
    updated_lines = []
    for line in env_lines:
        if line.strip().startswith('TELEGRAM_BOT_TOKEN='):
            updated_lines.append(f'TELEGRAM_BOT_TOKEN={token}\n')
            token_found = True
        else:
            updated_lines.append(line)
    
    # If token wasn't found, add it
    if not token_found:
        # Find the Telegram Bot Configuration section
        added = False
        for i, line in enumerate(updated_lines):
            if 'Telegram Bot Configuration' in line or 'TELEGRAM_BOT_TOKEN' in line:
                # Add after the comment line
                updated_lines.insert(i + 1, f'TELEGRAM_BOT_TOKEN={token}\n')
                added = True
                break
        if not added:
            # Add at the end
            updated_lines.append(f'\n# Telegram Bot Configuration\n')
            updated_lines.append(f'TELEGRAM_BOT_TOKEN={token}\n')
    
    # Write back to .env file
    with open(env_file, 'w', encoding='utf-8') as f:
        f.writelines(updated_lines)
    
    print(f"[INFO] Bot token saved to {env_file}")


def main():
    # Load environment variables from .env file
    load_dotenv()

    # Get bot token from environment variable (.env file) or input
    token = os.getenv('TELEGRAM_BOT_TOKEN')

    if not token:
        token = input("Enter your Telegram Bot Token: ").strip()
        
        if not token:
            print("❌ No bot token provided. Please enter a valid Telegram Bot Token.")
            return
        
        # Save token to .env file
        save_token_to_env(token)
        # Reload environment variables
        load_dotenv()
        token = os.getenv('TELEGRAM_BOT_TOKEN')

    if not token:
        print("❌ Failed to load bot token. Please check your .env file.")
        return

    # Get optional Instagram credentials
    ig_username = os.getenv('INSTAGRAM_USERNAME')
    ig_password = os.getenv('INSTAGRAM_PASSWORD')
    output_dir = os.getenv('DOWNLOAD_DIR')

    # Create and run bot (proxy configuration is handled automatically)
    bot = TelegramBot(token, ig_username, ig_password, output_dir=output_dir)

    try:
        bot.run()
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped by user")
    except Exception as e:
        print(f"❌ Error running bot: {e}")


if __name__ == "__main__":
    main()
