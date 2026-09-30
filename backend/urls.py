import http.client
import ipaddress
import re
import socket
import ssl
from urllib.parse import urlsplit, urljoin

from .errors import APIError

ALLOWED_HOSTS = frozenset({"shopee.co.th", "www.shopee.co.th", "s.shopee.co.th", "shope.ee"})


def validate_url(value, hosts=ALLOWED_HOSTS):
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise APIError(400, "INVALID_URL", "ลิงก์ไม่ถูกต้อง")
    if any(ord(c) <= 32 or ord(c) == 127 for c in value) or "\\" in value:
        raise APIError(400, "INVALID_URL", "ลิงก์มีอักขระที่ไม่อนุญาต")
    try:
        parts = urlsplit(value)
        if (parts.scheme.lower() != "https" or parts.hostname not in hosts
                or parts.username is not None or parts.password is not None
                or parts.port not in (None, 443)):
            raise ValueError("unsafe URL")
    except ValueError:
        raise APIError(400, "INVALID_URL", "ใช้ลิงก์ HTTPS ของ Shopee ที่อนุญาตเท่านั้น") from None
    return value


def product_identity(value):
    validate_url(value)
    parts = urlsplit(value)
    if parts.hostname not in {"shopee.co.th", "www.shopee.co.th"}:
        return None
    match = re.search(r"(?:-i\.(\d+)\.(\d+)(?:/|$)|/(?:universal-link/)?product/(\d+)/(\d+)(?:/|$))", parts.path)
    if match:
        return (match.group(1) or match.group(3), match.group(2) or match.group(4))
    return None


class ResolverUnavailable(Exception):
    """A blocked storefront/network cannot establish a destination automatically."""


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, hostname, address, timeout):
        super().__init__(hostname, timeout=timeout, context=ssl.create_default_context())
        self.address = address

    def connect(self):
        # Pin the validated address, but retain the original hostname for SNI/TLS checks.
        raw = socket.create_connection((self.address, 443), self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except BaseException:
            raw.close()
            raise


class SafeResolver:
    def __init__(self, timeout=8, max_redirects=5, dns=socket.getaddrinfo, connection_factory=PinnedHTTPSConnection):
        self.timeout = timeout
        self.max_redirects = max_redirects
        self.dns = dns
        self.connection_factory = connection_factory

    def addresses(self, hostname):
        try:
            records = self.dns(hostname, 443, type=socket.SOCK_STREAM)
        except OSError:
            raise ResolverUnavailable("DNS ติดต่อไม่ได้") from None
        addresses = list(dict.fromkeys(record[4][0] for record in records))
        if not addresses:
            raise ResolverUnavailable("ไม่มีผล DNS")
        # Reject the entire answer if even one address could reach a private service.
        for address in addresses:
            try:
                ip = ipaddress.ip_address(address)
                if not ip.is_global or (ip.version == 6 and ip.ipv4_mapped and not ip.ipv4_mapped.is_global):
                    raise ValueError("non-public destination")
            except ValueError:
                raise APIError(400, "UNSAFE_DESTINATION", "DNS ปลายทางไม่ใช่อินเทอร์เน็ตสาธารณะ") from None
        return addresses

    def resolve(self, value):
        current = validate_url(value)
        visited = set()
        for hop in range(self.max_redirects + 1):
            if current in visited:
                raise APIError(400, "REDIRECT_LOOP", "ปลายทางวนซ้ำ")
            visited.add(current)
            parts = urlsplit(current)
            address = self.addresses(parts.hostname)[0]
            connection = self.connection_factory(parts.hostname, address, self.timeout)
            try:
                target = parts.path or "/"
                if parts.query:
                    target += "?" + parts.query
                connection.request("GET", target, headers={"User-Agent": "AffiliateLinkHelper-DestinationCheck/1.0", "Range": "bytes=0-1023", "Accept": "text/html"})
                response = connection.getresponse()
                status = response.status
                location = response.getheader("Location")
                # Do not download/parse the product page, cookies or account data.
                if status in (301, 302, 303, 307, 308):
                    if not location or hop == self.max_redirects:
                        raise APIError(400, "INVALID_REDIRECT", "ตรวจ redirect ไม่สำเร็จ")
                    current = validate_url(urljoin(current, location))
                    continue
                if status in (200, 206):
                    if not product_identity(current):
                        raise APIError(400, "NOT_PRODUCT_URL", "ปลายทางไม่ใช่หน้าสินค้า Shopee ที่รองรับ")
                    return current
                if status in (404, 410):
                    raise APIError(400, "PRODUCT_NOT_FOUND", "ไม่พบสินค้า")
                raise ResolverUnavailable("เว็บสินค้ายังไม่อนุญาตให้ตรวจปลายทางอัตโนมัติ")
            except ssl.SSLCertVerificationError:
                raise APIError(400, "INVALID_TLS", "ใบรับรอง HTTPS ของปลายทางไม่ผ่านการตรวจ") from None
            except (OSError, http.client.HTTPException):
                raise ResolverUnavailable("เครือข่ายหรือการเชื่อมต่อเว็บสินค้าไม่พร้อม") from None
            finally:
                connection.close()
        raise APIError(400, "INVALID_REDIRECT", "redirect มากเกินไป")
