import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class LauncherTests(unittest.TestCase):
    def launch(self, service, values, mode=0o600):
        config = service / 'config.json'
        config.write_text(json.dumps(values))
        config.chmod(mode)
        environment = os.environ.copy()
        environment.pop('MAKEET_APPLE_WEB_CLIENT_ID', None)
        return subprocess.run(
            [sys.executable, str(Path(__file__).with_name('run.py')),
             '--service-dir', str(service)],
            env=environment, text=True, capture_output=True, check=False)

    def make_service(self, service):
        (service / 'bin').mkdir()
        binary = service / 'bin' / 'makeet'
        binary.write_text(
            '#!' + sys.executable + '\n'
            'import json, os\n'
            'print(json.dumps({key: os.getenv(key) for key in '
            '["MAKEET_APPLE_WEB_CLIENT_ID", "MAKEET_APPLE_CLIENT_IDS", '
            '"MAKEET_LISTEN", "MAKEET_DATABASE", "MAKEET_EMAIL_FROM"]}))\n')
        binary.chmod(0o700)

    def test_default_and_configured_web_signin_reach_child(self):
        with tempfile.TemporaryDirectory() as tmp:
            service = Path(tmp)
            self.make_service(service)
            values = {'MAKEET_APPLE_CLIENT_IDS': 'org.turinglabs.makeet'}
            result = self.launch(service, values)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            self.assertIsNone(output['MAKEET_APPLE_WEB_CLIENT_ID'])
            self.assertEqual(output['MAKEET_LISTEN'], '127.0.0.1:8086')
            self.assertEqual(output['MAKEET_DATABASE'], str(service.resolve() / 'data' / 'makeet.sqlite'))
            values['MAKEET_APPLE_WEB_CLIENT_ID'] = 'org.turinglabs.makeet.web'
            values['MAKEET_APPLE_CLIENT_IDS'] += ',org.turinglabs.makeet.web'
            result = self.launch(service, values)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            self.assertEqual(output['MAKEET_APPLE_WEB_CLIENT_ID'], values['MAKEET_APPLE_WEB_CLIENT_ID'])
            self.assertEqual(output['MAKEET_APPLE_CLIENT_IDS'], values['MAKEET_APPLE_CLIENT_IDS'])

    def test_email_sender_reaches_child_but_secret_config_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            service = Path(tmp)
            self.make_service(service)
            result = self.launch(service, {'MAKEET_EMAIL_FROM': 'noreply@noreply.makeet.app'})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['MAKEET_EMAIL_FROM'], 'noreply@noreply.makeet.app')
            result = self.launch(service, {'MAKEET_RESEND_API_KEY': 'fixture-secret'})
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')

    def test_unknown_nonstring_or_public_config_never_launches(self):
        with tempfile.TemporaryDirectory() as tmp:
            service = Path(tmp)
            self.make_service(service)
            cases = [({'UNEXPECTED': 'value'}, 0o600),
                     ({'MAKEET_APPLE_WEB_CLIENT_ID': True}, 0o600),
                     ({'MAKEET_APPLE_WEB_CLIENT_ID': 'org.turinglabs.makeet.web'}, 0o644)]
            for values, mode in cases:
                with self.subTest(values=values, mode=mode):
                    result = self.launch(service, values, mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, '')
                    self.assertEqual(result.stderr.strip(), 'Makeet runtime configuration unavailable')


if __name__ == '__main__':
    unittest.main()
