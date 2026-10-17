"""Restrict Makeet origin traffic to Cloudflare and stamp a trusted client address."""
import ipaddress

HOSTS = frozenset({'makeet.app', 'api.makeet.app', 'www.makeet.app'})
# https://www.cloudflare.com/ips-v4 and /ips-v6, checked 2026-10-16.
NETWORKS = tuple(ipaddress.ip_network(value) for value in '''
173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
'''.split())


def prepare(head, host, peer):
    if host not in HOSTS:
        return head
    try:
        address = ipaddress.ip_address(peer)
    except ValueError:
        return None
    if not any(address in network for network in NETWORKS):
        return None
    split = head.find(b'\r\n\r\n')
    if split < 0:
        return None
    lines = head[:split].split(b'\r\n')
    client = []
    kept = [lines[0]]
    for line in lines[1:]:
        name, separator, value = line.partition(b':')
        if not separator or name[:1] in (b' ', b'\t'):
            return None
        name = name.strip().lower()
        if name == b'cf-connecting-ip':
            client.append(value.strip())
        if name not in (b'x-makeet-client-ip', b'x-forwarded-for', b'forwarded'):
            kept.append(line)
    if len(client) != 1:
        return None
    try:
        client_ip = ipaddress.ip_address(client[0].decode('ascii'))
    except (ValueError, UnicodeError):
        return None
    kept.append(b'X-Makeet-Client-IP: ' + str(client_ip).encode('ascii'))
    return b'\r\n'.join(kept) + head[split:]
