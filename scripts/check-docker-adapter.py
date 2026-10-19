#!/usr/bin/env python3
"""Read-only adapter check against a local fake Engine API, never a real Docker daemon."""
import http.server
import json
import os
from pathlib import Path
import socketserver
import subprocess
import tempfile
import threading

docker = os.environ.get("HARBOR_DOCKER", "/usr/local/bin/docker")
requests = []

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        requests.append(self.path)
        if self.path.endswith("/_ping"):
            body = b"OK"
        elif "/containers/json" in self.path:
            body = json.dumps([{
                "Id": "a" * 64, "Names": ["/harbor-fixture-web"], "Image": "nginx:alpine",
                "ImageID": "sha256:" + "b" * 64, "Command": "nginx", "Created": 1720000000,
                "State": "running", "Status": "Up 2 minutes", "Labels": {},
                "Ports": [{"IP": "127.0.0.1", "PrivatePort": 80, "PublicPort": 18080, "Type": "tcp"}],
                "HostConfig": {"NetworkMode": "bridge"}, "NetworkSettings": {"Networks": {}}, "Mounts": []
            }]).encode()
        elif "/images/json" in self.path:
            body = json.dumps([{
                "Id": "sha256:" + "b" * 64, "RepoTags": ["nginx:alpine"], "RepoDigests": [],
                "Created": 1720000000, "Size": 22000000, "SharedSize": -1, "Containers": 1, "Labels": {}
            }]).encode()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("API-Version", "1.51")
        self.send_header("OSType", "linux")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

with tempfile.TemporaryDirectory(prefix="harbor-api-", dir="/tmp") as directory:
    socket = str(Path(directory) / "test.sock")
    server = Server(socket, Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        env = {k: v for k, v in os.environ.items() if k not in {
            "DOCKER_CONTEXT", "DOCKER_HOST", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH", "DOCKER_API_VERSION"}}
        def run(*args):
            return subprocess.check_output([docker, "--host", "unix://" + socket, *args], env=env, text=True, timeout=15)
        container = json.loads(run("ps", "--all", "--no-trunc", "--format", "{{json .}}"))
        assert container["Names"] == "harbor-fixture-web"
        assert container["State"] == "running"
        assert "18080" in container["Ports"]
        image = json.loads(run("image", "ls", "--format", "{{json .}}"))
        assert image["Repository"] == "nginx" and image["Tag"] == "alpine"
        assert all("/containers/json" in p or "/images/json" in p or p.endswith("/_ping") for p in requests)
        print("PASS: real Docker CLI → isolated Unix socket → container/image JSON schemas")
        print("This verifies the adapter only, not Apple Container or Socktainer compatibility.")
    finally:
        server.shutdown()
        server.server_close()
