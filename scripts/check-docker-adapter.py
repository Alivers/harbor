#!/usr/bin/env python3
"""Read-only adapter check against a local fake Engine API, never a real Docker daemon.

Runs the real Docker CLI + Compose plugin with the same arguments Harbor uses to list a
Compose project's containers, and checks the JSON fields `ContainerRow` decodes.
"""
import http.server
import json
import os
from pathlib import Path
import shutil
import socketserver
import subprocess
import tempfile
import threading

docker = os.environ.get("HARBOR_DOCKER") or shutil.which("docker") or "/usr/local/bin/docker"
example = Path(__file__).resolve().parents[1] / "Examples/web-stack"
container_id = "a" * 64
labels = {"com.docker.compose.project": "harbor-smoke", "com.docker.compose.service": "web",
          "com.docker.compose.container-number": "1", "com.docker.compose.oneoff": "False"}
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
                "Id": container_id, "Names": ["/harbor-smoke-web-1"], "Image": "nginx:alpine",
                "ImageID": "sha256:" + "b" * 64, "Command": "nginx", "Created": 1720000000,
                "State": "running", "Status": "Up 2 minutes", "Labels": labels,
                "Ports": [{"IP": "127.0.0.1", "PrivatePort": 80, "PublicPort": 18080, "Type": "tcp"}],
                "HostConfig": {"NetworkMode": "bridge"}, "NetworkSettings": {"Networks": {}}, "Mounts": []
            }]).encode()
        elif self.path.endswith("/containers/" + container_id + "/json"):
            body = json.dumps({
                "Id": container_id, "Name": "/harbor-smoke-web-1", "Created": "2026-01-01T00:00:00Z",
                "State": {"Status": "running", "Running": True, "ExitCode": 0},
                "Image": "sha256:" + "b" * 64, "Config": {"Image": "nginx:alpine", "Labels": labels},
                "HostConfig": {"NetworkMode": "bridge"}, "Mounts": [],
                "NetworkSettings": {"Ports": {"80/tcp": [{"HostIp": "127.0.0.1", "HostPort": "18080"}]}, "Networks": {}}
            }).encode()
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
            "DOCKER_CONTEXT", "DOCKER_HOST", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH", "DOCKER_API_VERSION",
            "COMPOSE_FILE", "COMPOSE_PROJECT_NAME", "COMPOSE_PROFILES"}}
        # Same shape as RuntimeConfig.composeCommand(project, ComposeProject.serviceQuery).
        output = subprocess.check_output([
            docker, "--host", "unix://" + socket, "compose", "--ansi", "never",
            "--project-directory", str(example), "--file", str(example / "compose.yaml"),
            "ps", "--all", "--format", "json"], env=env, cwd=example, text=True, timeout=30)
        rows = [json.loads(line) for line in output.splitlines() if line.strip()]
        assert len(rows) == 1, output
        row = rows[0]
        assert row["ID"] == container_id[:12]
        assert row["Names"] == "harbor-smoke-web-1"
        assert row["Image"] == "nginx:alpine"
        assert row["State"] == "running"
        assert row["Status"] == "Up 2 minutes"
        assert "18080" in row["Ports"]
        assert requests and all(p.endswith("/_ping") or "/containers/" in p for p in requests), requests
        print("PASS: real Docker CLI + Compose → isolated Unix socket → compose ps JSON fields")
        print("This verifies the adapter only, not Apple Container or Socktainer compatibility.")
    finally:
        server.shutdown()
        server.server_close()
