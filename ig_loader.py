import instaloader
import os
import tempfile
import shutil
from pathlib import Path
from datetime import datetime
import json
import time

from dotenv import load_dotenv

from proxy import proxy_config

load_dotenv()

# region agent log
def _agent_debug_log(run_id, hypothesis_id, location, message, data=None):
    try:
        entry = {
            "sessionId": "18e1f7",
            "runId": run_id,
            "hypothesisId": hypothesis_id,
            "location": location,
            "message": message,
            "data": data or {},
            "timestamp": int(time.time() * 1000),
        }
        log_path = os.path.join(os.path.dirname(__file__), "debug-18e1f7.log")
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        # Intentionally ignore logging failures
        pass
# endregion


class InstagramDownloader:
    def __init__(self, output_dir=None, username=None, password=None):
        if output_dir is None:
            output_dir = os.getenv("DOWNLOAD_DIR", "downloads")
            if not os.path.isabs(output_dir):
                output_dir = os.path.join(os.getcwd(), output_dir)
        self.output_dir = os.path.abspath(output_dir)
        # Ensure the downloads directory exists and is writable
        try:
            Path(self.output_dir).mkdir(exist_ok=True)
            # Test if directory is writable
            test_file = os.path.join(self.output_dir, '.test')
            with open(test_file, 'w') as f:
                f.write('test')
            os.remove(test_file)
            print(f"[INFO] Download directory: {self.output_dir}")
        except Exception as e:
            print(f"[ERROR] Cannot create/write to download directory {self.output_dir}: {e}")
            # Fallback to system temp directory
            self.output_dir = tempfile.gettempdir()
            print(f"[INFO] Using fallback directory: {self.output_dir}")

        self.username = username
        self.password = password
        self.proxy_config = proxy_config
        self.session_file = os.path.join(
            os.path.dirname(__file__),
            os.getenv("INSTAGRAM_SESSION_FILE", "instagram_session"),
        )

    def download(self, url):
        """Download Instagram post (image/video/carousel) using instaloader."""

        # region agent log
        _agent_debug_log(
            run_id="pre-fix-1",
            hypothesis_id="H1",
            location="ig_loader.py:44",
            message="download() called",
            data={"url": url},
        )
        # endregion

        def create_instaloader_instance() -> instaloader.Instaloader:
            """Create a configured Instaloader instance without applying proxies."""
            return instaloader.Instaloader(
                download_videos=True,
                download_video_thumbnails=False,
                download_geotags=False,
                download_comments=False,
                save_metadata=False,
                compress_json=False,
                post_metadata_txt_pattern='',
                quiet=True,  # Suppress instaloader output to avoid Unicode issues
                # Try different user agent to avoid detection
                user_agent=(
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/91.0.4472.124 Safari/537.36'
                ),
                # Additional settings to avoid rate limiting
                max_connection_attempts=3,
                request_timeout=30.0,
                dirname_pattern=os.path.join(self.output_dir, "{target}"),
            )

        def configure_proxies(L: instaloader.Instaloader) -> None:
            """Apply proxy settings to the Instaloader session if configured in .env."""
            if self.proxy_config.enabled:
                self.proxy_config.configure_socket_proxy()
                proxy_config_dict = self.proxy_config.instaloader
                if hasattr(L.context, "_session"):
                    L.context._session.proxies.update(proxy_config_dict["proxies"])
                print(f"[INFO] SOCKS5 proxy configured for instaloader: {self.proxy_config.url}")

        def load_or_login(L: instaloader.Instaloader) -> bool:
            """Load saved session and/or perform login. Returns True on success."""
            # Try to load existing session if available
            session_file = self.session_file
            if os.path.exists(session_file) and self.username:
                try:
                    L.load_session_from_file(self.username, session_file)
                    print("[SUCCESS] Loaded existing session")
                except Exception as e:
                    print(f"[WARNING] Could not load session: {e}")
                    # Remove corrupted session file
                    try:
                        os.remove(session_file)
                    except Exception:
                        pass

            # Login if credentials provided
            if self.username and self.password:
                try:
                    L.login(self.username, self.password)
                    print(f"[SUCCESS] Logged in as {self.username}")
                    # Save session for future use
                    L.save_session_to_file(self.session_file)
                    print(f"[SUCCESS] Session saved to {self.session_file}")
                except Exception as e:
                    print(f"[ERROR] Login failed: {e}")
                    return False

            return True

        def do_download(L: instaloader.Instaloader) -> dict | None:
            """Perform the actual download logic with a prepared Instaloader instance."""
            # Extract shortcode from URL
            if "/reel/" in url:
                shortcode = url.split("/reel/")[1].split("/")[0]
            else:
                shortcode = url.split("/p/")[1].split("/")[0]

            # Get post
            post = instaloader.Post.from_shortcode(L.context, shortcode)

            # Check if it's a carousel (multiple media)
            if post.mediacount > 1:
                # Handle carousel posts
                print(f"\n[SUCCESS] Downloading carousel with {post.mediacount} items!")

                # Create temporary directory for download
                L.download_post(post, target=post.shortcode)

                # Find downloaded files
                downloaded_files = []
                for root, dirs, files in os.walk(self.output_dir + os.sep + post.shortcode):
                    for file in files:
                        if file.endswith((".jpg", ".jpeg", ".png", ".mp4", ".mov")):
                            src_path = os.path.join(root, file)
                            try:
                                downloaded_files.append(src_path)
                            except Exception as copy_error:
                                print(f"[ERROR] Failed to collect {src_path}: {copy_error}")

                    if downloaded_files:
                        # Return carousel info
                        return {
                            "is_carousel": True,
                            "filenames": downloaded_files,
                            "title": post.title or f"Post by {post.owner_username}",
                            "uploader": post.owner_username,
                            "description": post.caption or "",
                            "thumbnail": None,  # Instaloader doesn't provide separate thumbnails
                            "duration": post.video_duration if post.is_video else 0,
                            "view_count": 0,  # Instaloader doesn't provide view counts
                            "like_count": post.likes,
                            "comment_count": post.comments,
                            "upload_date": post.date_utc.strftime("%Y%m%d") if post.date_utc else "",
                            "webpage_url": url,
                        }

            else:
                # Handle single post
                print("\n[SUCCESS] Downloading single post!")

                L.download_post(post, target=post.shortcode)

                # Find the downloaded file
                downloaded_file = None
                for root, dirs, files in os.walk(self.output_dir + os.sep + post.shortcode):
                    for file in files:
                        if file.endswith((".jpg", ".jpeg", ".png", ".mp4", ".mov")):
                            src_path = os.path.join(root, file)
                            try:
                                downloaded_file = src_path
                            except Exception as copy_error:
                                print(f"[ERROR] Failed to collect {src_path}: {copy_error}")
                            break

                    if downloaded_file:
                        break

                if downloaded_file:
                    # Return single post info
                    return {
                        "is_carousel": False,
                        "filename": downloaded_file,
                        "title": post.title or f"Post by {post.owner_username}",
                        "uploader": post.owner_username,
                        "description": post.caption or "",
                        "thumbnail": None,  # Instaloader doesn't provide separate thumbnails
                        "duration": post.video_duration if post.is_video else 0,
                        "view_count": 0,  # Instaloader doesn't provide view counts
                        "like_count": post.likes,
                        "comment_count": post.comments,
                        "upload_date": post.date_utc.strftime("%Y%m%d") if post.date_utc else "",
                        "webpage_url": url,
                    }

            return None

        # --- Main download flow ---
        L = create_instaloader_instance()
        configure_proxies(L)

        # region agent log
        _agent_debug_log(
            run_id="pre-fix-1",
            hypothesis_id="H6",
            location="ig_loader.py:217",
            message="Instaloader instance created",
            data={},
        )
        # endregion

        if not load_or_login(L):
            # region agent log
            _agent_debug_log(
                run_id="pre-fix-1",
                hypothesis_id="H7",
                location="ig_loader.py:221",
                message="load_or_login() returned False",
                data={},
            )
            # endregion
            return None

        # region agent log
        _agent_debug_log(
            run_id="pre-fix-1",
            hypothesis_id="H8",
            location="ig_loader.py:224",
            message="Calling do_download()",
            data={},
        )
        # endregion

        try:
            result = do_download(L)

            # region agent log
            _agent_debug_log(
                run_id="pre-fix-1",
                hypothesis_id="H8",
                location="ig_loader.py:225",
                message="do_download() returned",
                data={"has_result": result is not None},
            )
            # endregion

            if result is not None:
                return result
            print("[WARNING] Instaloader finished without a downloadable result")

        except Exception as e:
            print(f"\n[ERROR] Instaloader failed: {e}")

            # region agent log
            _agent_debug_log(
                run_id="pre-fix-1",
                hypothesis_id="H2",
                location="ig_loader.py:232",
                message="Instaloader exception",
                data={"error": str(e)},
            )
            # endregion

        # Fall back to yt-dlp
        print("[INFO] Falling back to yt-dlp...")

        # region agent log
        _agent_debug_log(
            run_id="pre-fix-1",
            hypothesis_id="H4",
            location="ig_loader.py:265",
            message="Falling back to yt-dlp",
            data={},
        )
        # endregion

        try:
            return self.download_with_yt_dlp(url)
        except Exception as fallback_error:
            print(f"[ERROR] yt-dlp fallback also failed: {fallback_error}")

            print("\n[INFO] This post may require authentication or be restricted.")
            print("[INFO] Try adding Instagram credentials to your .env file:")
            print("       INSTAGRAM_USERNAME=your_username")
            print("       INSTAGRAM_PASSWORD=your_password")

            return None

    def download_with_yt_dlp(self, url):
        """Fallback method using yt-dlp when instaloader fails"""
        try:
            import yt_dlp
        except ImportError:
            print("[ERROR] yt-dlp not available for fallback")

            # region agent log
            _agent_debug_log(
                run_id="pre-fix-1",
                hypothesis_id="H9",
                location="ig_loader.py:419",
                message="yt-dlp import failed",
                data={},
            )
            # endregion

            return None

        ydl_opts = {
            'outtmpl': f'{self.output_dir}/%(id)s.%(ext)s',
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
            'format': 'best',
            'nocheckcertificate': True,
            'ignoreerrors': True,
            'no_color': True,
        }
        ydl_opts.update(self.proxy_config.ytdlp)

        try:
            # region agent log
            _agent_debug_log(
                run_id="pre-fix-1",
                hypothesis_id="H9",
                location="ig_loader.py:441",
                message="download_with_yt_dlp() called",
                data={},
            )
            # endregion

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                print(f"[FALLBACK] Trying yt-dlp for: {url}")
                info = ydl.extract_info(url, download=True)

                # region agent log
                _agent_debug_log(
                    run_id="pre-fix-1",
                    hypothesis_id="H9",
                    location="ig_loader.py:448",
                    message="yt-dlp extract_info() returned",
                    data={"has_info": bool(info)},
                )
                # endregion

                if info:
                    filename = ydl.prepare_filename(info)

                    # Check if file was actually downloaded
                    if filename and os.path.exists(filename):
                        # Handle carousel detection for yt-dlp
                        is_carousel = 'entries' in info and info['entries'] and len(info['entries']) > 1

                        if is_carousel:
                            print(f"[FALLBACK] yt-dlp detected carousel")
                            # For carousel, we'd need more complex logic here
                            # For now, just return the first file
                            pass

                        result = {
                            'is_carousel': False,  # yt-dlp fallback handles single files for now
                            'filename': filename,
                            'title': info.get('title', ''),
                            'uploader': info.get('uploader', ''),
                            'description': info.get('description', ''),
                            'thumbnail': info.get('thumbnail', ''),
                            'duration': info.get('duration', 0),
                            'view_count': info.get('view_count', 0),
                            'like_count': info.get('like_count', 0),
                            'comment_count': info.get('comment_count', 0),
                            'upload_date': info.get('upload_date', ''),
                            'webpage_url': info.get('webpage_url', url)
                        }

                        print(f"[FALLBACK] Successfully downloaded with yt-dlp: {filename}")
                        return result
                    else:
                        print("[FALLBACK] yt-dlp failed to download file")

                        # region agent log
                        _agent_debug_log(
                            run_id="pre-fix-1",
                            hypothesis_id="H9",
                            location="ig_loader.py:479",
                            message="yt-dlp did not produce a file",
                            data={"filename": filename or ""},
                        )
                        # endregion

                        return None
                else:
                    print("[FALLBACK] yt-dlp failed to extract info")

                    # region agent log
                    _agent_debug_log(
                        run_id="pre-fix-1",
                        hypothesis_id="H9",
                        location="ig_loader.py:487",
                        message="yt-dlp extract_info() returned no info",
                        data={},
                    )
                    # endregion

                    return None

        except Exception as e:
            print(f"[FALLBACK] yt-dlp failed: {e}")

            # region agent log
            _agent_debug_log(
                runId="pre-fix-1",
                hypothesis_id="H5",
                location="ig_loader.py:495",
                message="yt-dlp fallback exception",
                data={"error": str(e)},
            )
            # endregion

            return None

    def download_multiple(self, urls):
        """Download multiple Instagram posts"""
        results = []
        for url in urls:
            result = self.download(url)
            results.append(result)
            print("-" * 50)
        return results

if __name__ == "__main__":
    print("=" * 60)
    print("Instagram Multi-Media Downloader")
    print("Posts • Reels • Stories • Carousels")
    print("=" * 60)
    

    downloader = InstagramDownloader()
    post_url = input("\nEnter Instagram post URL: ").strip()
    result = downloader.download(post_url)