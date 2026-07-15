"""
Instagram Post Downloader using instagrapi
Install: pip install instagrapi
"""

from instagrapi import Client
from pathlib import Path
import re

class InstagramDownloader:
    def __init__(self, output_dir='downloads'):
        self.cl = Client()
        self.output_dir = output_dir
        Path(output_dir).mkdir(exist_ok=True)
        
        # Optional: Login for better reliability (can work without login too)
        self.logged_in = False
    
    def login(self, username, password):
        """Optional login for more reliable access"""
        try:
            self.cl.login(username, password)
            self.logged_in = True
            print("✓ Logged in successfully")
            return True
        except Exception as e:
            print(f"✗ Login failed: {e}")
            return False
    
    def extract_media_pk(self, url):
        """Extract media PK from Instagram URL"""
        # Extract shortcode from URL
        patterns = [
            r'instagram\.com/p/([A-Za-z0-9_-]+)',
            r'instagram\.com/reel/([A-Za-z0-9_-]+)',
            r'instagram\.com/tv/([A-Za-z0-9_-]+)'
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                shortcode = match.group(1)
                # Convert shortcode to media_pk
                media_pk = self.cl.media_pk_from_code(shortcode)
                return media_pk
        
        return None
    
    def download_post(self, url):
        """Download Instagram post (photo/video/album)"""
        try:
            print(f"\nProcessing: {url}")
            
            # Get media PK from URL
            media_pk = self.extract_media_pk(url)
            if not media_pk:
                print("✗ Invalid Instagram URL")
                return None
            
            # Get media info
            media = self.cl.media_info(media_pk)
            
            print(f"Type: {media.media_type}")
            print(f"Caption: {media.caption_text[:100] if media.caption_text else 'No caption'}...")
            
            # Download based on media type
            if media.media_type == 1:  # Photo
                print("Downloading photo...")
                path = self.cl.photo_download(media_pk, self.output_dir)
                print(f"✓ Downloaded: {path}")
                return path
            
            elif media.media_type == 2:  # Video/Reel
                print("Downloading video...")
                path = self.cl.video_download(media_pk, self.output_dir)
                print(f"✓ Downloaded: {path}")
                return path
            
            elif media.media_type == 8:  # Album/Carousel
                print("Downloading album/carousel...")
                paths = self.cl.album_download(media_pk, self.output_dir)
                print(f"✓ Downloaded {len(paths)} items:")
                for p in paths:
                    print(f"  - {p}")
                return paths
            
            else:
                print(f"✗ Unknown media type: {media.media_type}")
                return None
                
        except Exception as e:
            print(f"✗ Error: {e}")
            return None
    
    def download_by_shortcode(self, shortcode):
        """Download directly by shortcode (e.g., 'CXYz123abc')"""
        try:
            media_pk = self.cl.media_pk_from_code(shortcode)
            url = f"https://www.instagram.com/p/{shortcode}/"
            return self.download_post(url)
        except Exception as e:
            print(f"✗ Error: {e}")
            return None
    
    def download_user_posts(self, username, amount=10):
        """Download recent posts from a user"""
        try:
            print(f"\nFetching posts from @{username}...")
            user_id = self.cl.user_id_from_username(username)
            medias = self.cl.user_medias(user_id, amount)
            
            print(f"Found {len(medias)} posts. Downloading...")
            
            downloaded = []
            for media in medias:
                print(f"\n[{media.code}]")
                
                if media.media_type == 1:
                    path = self.cl.photo_download(media.pk, self.output_dir)
                elif media.media_type == 2:
                    path = self.cl.video_download(media.pk, self.output_dir)
                elif media.media_type == 8:
                    path = self.cl.album_download(media.pk, self.output_dir)
                else:
                    continue
                
                downloaded.append(path)
                print(f"✓ Downloaded")
            
            print(f"\n✓ Total downloaded: {len(downloaded)}")
            return downloaded
            
        except Exception as e:
            print(f"✗ Error: {e}")
            return None


def main():
    print("=" * 60)
    print("Instagram Downloader with instagrapi")
    print("=" * 60)
    
    downloader = InstagramDownloader()
    
    # Optional: Login (not required but more reliable)
    use_login = input("\nLogin to Instagram? (y/n, recommended for better reliability): ").strip().lower()
    
    if use_login == 'y':
        username = input("Username: ").strip()
        password = input("Password: ").strip()
        downloader.login(username, password)
        print()
    
    print("\nOptions:")
    print("1. Download single post by URL")
    print("2. Download single post by shortcode")
    print("3. Download user's recent posts")
    
    choice = input("\nEnter choice (1-3): ").strip()
    
    if choice == '1':
        url = input("Enter Instagram post URL: ").strip()
        downloader.download_post(url)
    
    elif choice == '2':
        shortcode = input("Enter shortcode (e.g., CXYz123abc): ").strip()
        downloader.download_by_shortcode(shortcode)
    
    elif choice == '3':
        username = input("Enter username (without @): ").strip()
        amount = input("Number of posts to download (default 10): ").strip()
        amount = int(amount) if amount else 10
        downloader.download_user_posts(username, amount)
    
    else:
        print("Invalid choice")


if __name__ == "__main__":
    main()