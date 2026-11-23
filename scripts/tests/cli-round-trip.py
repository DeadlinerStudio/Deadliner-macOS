"""Exercise the native Mac editor's commands, two independent databases, and the installed CLI."""
import json
import subprocess
import sys
import tempfile
import time

binary, probe = sys.argv[1:]
with tempfile.TemporaryDirectory() as profile, tempfile.TemporaryDirectory() as mac:
    cli = [binary, "--json", "--data-dir", profile]
    def task(*args):
        for _ in range(20):
            proc = subprocess.run([*cli, "task", *args], stdout=subprocess.PIPE)
            value = json.loads(proc.stdout)
            if value["ok"]:
                return value["data"]
            if value["error"]["code"] != "BUSY":
                raise RuntimeError(value["error"])
            time.sleep(0.15)
        raise TimeoutError("CLI profile remained busy")
    task("add", "--uid", "quality-check", "--title", "上线质量复核", "--due", "2026-11-23T18:30:00+08:00")
    with subprocess.Popen([*cli, "serve", "--allow-writes"], stdout=subprocess.PIPE) as service:
        try:
            code = json.loads(service.stdout.readline())["data"]["connectionCode"]
            with subprocess.Popen([probe, mac], stdin=subprocess.PIPE, text=True) as native:
                try:
                    native.stdin.write(code + "\n")
                    native.stdin.close()
                    for _ in range(40):
                        row = task("get", "quality-check")
                        if row["note"] == "Mac 已复核":
                            break
                        if native.poll() is not None: raise RuntimeError("Mac probe exited early")
                        time.sleep(0.5)
                    assert row["note"] == "Mac 已复核" and row.get("dueAt") is None
                    assert row["subtasks"][0]["isCompleted"]
                    assert task("list", "--query", "Mac only")["total"] == 1
                    task("update", "quality-check", "--note", "终端已确认")
                    assert native.wait(timeout=30) == 0
                    print("PASS: native task commands, CLI edits, independent tasks, subtasks, date clearing, stale draft")
                finally:
                    if native.poll() is None: native.terminate()
        finally:
            service.terminate()
            service.wait(timeout=5)
