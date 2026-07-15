"""
Proxy configuration module for SOCKS5 proxy support
"""

import os
import socket

import socks
from dotenv import load_dotenv

load_dotenv()


class ProxyConfig:
    """Configuration class for SOCKS5 proxy settings"""

    def __init__(self, host: str = None, port: int = None):
        env_host = os.getenv("PROXY_HOST")
        env_port = os.getenv("PROXY_PORT")

        if env_host and env_port:
            self.enabled = True
            self.host = host or env_host
            self.port = port or int(env_port)
            self.url = f"socks5://{self.host}:{self.port}"
            print(f"[INFO] SOCKS5 proxy enabled: {self.url}")
        else:
            self.enabled = False
            self.host = None
            self.port = None
            self.url = None
            print("[INFO] SOCKS5 proxy disabled (not configured in .env)")

    def configure_socket_proxy(self) -> bool:
        if not self.enabled:
            return True

        try:
            socks.setdefaultproxy(socks.PROXY_TYPE_SOCKS5, self.host, self.port)
            socket.socket = socks.socksocket
            print(f"[INFO] Global socket proxy configured: {self.url}")
            return True
        except ImportError:
            print("[WARNING] PySocks not installed. Socket proxy not available.")
            print("Install with: pip install PySocks")
            return False
        except Exception as e:
            print(f"[WARNING] Failed to configure socket proxy: {e}")
            return False

    @property
    def instaloader(self) -> dict:
        if not self.enabled:
            return {"proxies": {}}

        return {
            "proxies": {
                "http": self.url,
                "https": self.url,
            }
        }

    @property
    def ytdlp(self) -> dict:
        if not self.enabled:
            return {}

        return {"proxy": self.url}

    @property
    def telegram(self) -> dict:
        config = {
            "connect_timeout": 5,
            "read_timeout": 5,
        }

        if self.enabled:
            config["proxy"] = self.url

        return config

    def __str__(self) -> str:
        if not self.enabled:
            return "ProxyConfig(enabled=False)"
        return f"ProxyConfig(enabled=True, host='{self.host}', port={self.port}, url='{self.url}')"

    def __repr__(self) -> str:
        return self.__str__()


proxy_config = ProxyConfig()
