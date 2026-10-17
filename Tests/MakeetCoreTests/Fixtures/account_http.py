import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

counts = {"refresh": 0, "sync": 0, "delete": 0, "push": 0}
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/counts":
            with lock:
                self.reply(200, counts)
        else:
            self.reply(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path.startswith("/v1/devices/") and self.headers.get("Authorization") == "Bearer fixture-next":
            if body.get("installation_secret") != "fixture-installation" or not body.get("message_id"):
                self.reply(400, {"error": "invalid_device_request"})
            elif self.path.endswith("/test"):
                self.reply(200, {"message_id": body["message_id"], "status": "accepted", "confirmed_at": 0})
            else:
                self.reply(204, {})
        elif self.path == "/v1/auth/challenges":
            self.reply(201, {"id": "fixture", "nonce": "fixture-nonce", "expires_at": 1900000000})
        elif self.path == "/v1/auth/refresh":
            with lock:
                counts["refresh"] += 1
                attempt = counts["refresh"]
            time.sleep(0.15)
            if attempt != 1 or body.get("refresh_token") != "fixture-refresh":
                self.reply(401, {"error": "invalid_session"})
            else:
                self.reply(200, {"access_token": "fixture-next", "refresh_token": "fixture-rotated", "expires_in": 900,
                    "user": {"id": "d604b64a-f819-4822-840a-8c472d388632", "email": "test@example.invalid"}})
        elif self.path == "/v1/sync" and self.headers.get("Authorization") == "Bearer fixture-next":
            with lock:
                counts["sync"] += 1
            self.reply(200, {"cursor": 0, "has_more": False, "changes": [], "applied": []})
        else:
            self.reply(401, {"error": "unauthorized"})

    def do_DELETE(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path.startswith("/v1/devices/") and self.headers.get("Authorization") == "Bearer fixture-next" and body.get("installation_secret") == "fixture-installation":
            self.reply(204, {})
            return
        if self.path != "/v1/me" or self.headers.get("Authorization") != "Bearer fixture-next" or body != {"confirmation": "DELETE"}:
            self.reply(401, {"error": "unauthorized"})
            return
        with lock:
            counts["delete"] += 1
            attempt = counts["delete"]
        if attempt == 1:
            self.reply(503, {"error": "provider_revocation_unavailable"})
        else:
            self.reply(204, {})

    def do_PUT(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if not self.path.startswith("/v1/devices/") or self.headers.get("Authorization") != "Bearer fixture-next":
            self.reply(401, {"error": "unauthorized"})
            return
        expected = {"installation_secret", "token", "topic", "environment", "language", "time_zone", "reminders_enabled", "reminder_hour", "reminder_minute"}
        if set(body) != expected or body["time_zone"] != "Europe/Rome" or body["installation_secret"] != "fixture-installation":
            self.reply(400, {"error": "invalid_device"})
            return
        with lock:
            counts["push"] += 1
        self.reply(200, {"registered": True, "accepted_at": 123, "confirmed_at": 0})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
