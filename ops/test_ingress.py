import unittest
import makeet_ingress


class IngressTests(unittest.TestCase):
    def test_makeet_requires_cloudflare_and_one_valid_client_ip(self):
        head=b'POST /v1/auth/challenges HTTP/1.1\r\nHost: api.makeet.app\r\nCF-Connecting-IP: 203.0.113.2\r\nX-Makeet-Client-IP: 1.2.3.4\r\nX-Forwarded-For: 9.9.9.9\r\nContent-Length: 2\r\n\r\n{}'
        self.assertIsNone(makeet_ingress.prepare(head,'api.makeet.app','203.0.113.1'))
        output=makeet_ingress.prepare(head,'api.makeet.app','104.16.1.1')
        self.assertIn(b'X-Makeet-Client-IP: 203.0.113.2\r\n',output)
        self.assertNotIn(b'1.2.3.4',output)
        self.assertNotIn(b'9.9.9.9',output)
        self.assertTrue(output.endswith(b'\r\n\r\n{}'))
        duplicate=head.replace(b'Content-Length:',b'CF-Connecting-IP: 203.0.113.3\r\nContent-Length:')
        self.assertIsNone(makeet_ingress.prepare(duplicate,'api.makeet.app','104.16.1.1'))
        self.assertIsNone(makeet_ingress.prepare(head.replace(b'203.0.113.2',b'invalid'),'api.makeet.app','104.16.1.1'))

    def test_other_hosts_are_byte_for_byte_unchanged(self):
        head=b'GET / HTTP/1.1\r\nHost: unrelated.example\r\n\r\n'
        self.assertIs(makeet_ingress.prepare(head,'unrelated.example','203.0.113.1'),head)

    def test_ipv6_peer_and_address_are_supported(self):
        head=b'GET / HTTP/1.1\r\nHost: makeet.app\r\nCF-Connecting-IP: 2001:db8::7\r\n\r\n'
        output=makeet_ingress.prepare(head,'makeet.app','2606:4700::1')
        self.assertIn(b'X-Makeet-Client-IP: 2001:db8::7\r\n',output)


if __name__=='__main__':
    unittest.main()
