"""Connect the production Swift transport to a native CLI in a temporary profile."""
import json
import subprocess
import sys
import tempfile

binary, probe = sys.argv[1:]
with tempfile.TemporaryDirectory() as profile:
    cli = [binary, "--json", "--data-dir", profile]
    def task(*args):
        return json.loads(subprocess.check_output([*cli, "task", *args]))["data"]
    task("add", "--uid", "quality-check", "--title", "上线质量复核", "--due", "2026-11-23T18:30:00+08:00")
    with subprocess.Popen([*cli, "serve", "--allow-writes"], stdout=subprocess.PIPE) as service:
        try:
            code = json.loads(service.stdout.readline())["data"]["connectionCode"]
            subprocess.run([probe], input=code + "\n", text=True, timeout=30, check=True)
            row = task("get", "quality-check")
            assert row["note"] == "Mac 已复核" and row.get("dueAt") is None
            print("PASS: terminal fixture -> Swift snapshot -> Swift edit -> CLI readback; stale edit rejected")
        finally:
            service.terminate()
            service.wait(timeout=5)
