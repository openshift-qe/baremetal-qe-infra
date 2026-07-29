import asyncio
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

app = FastAPI()

STATIC_DIR = Path(__file__).parent / "static"


@app.get("/")
async def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/status")
async def api_status():
    data = await collect_all()
    return JSONResponse(data)


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            data = await collect_all()
            await ws.send_json(data)
            await asyncio.sleep(3)
    except WebSocketDisconnect:
        pass


async def collect_all() -> dict:
    loop = asyncio.get_event_loop()
    containers, units, host = await asyncio.gather(
        loop.run_in_executor(None, get_containers),
        loop.run_in_executor(None, get_systemd_units),
        loop.run_in_executor(None, get_host_metrics),
    )
    return {
        "containers": containers,
        "systemd_units": units,
        "host": host,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _run(cmd: list[str], timeout: int = 10) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except Exception:
        return ""


def get_containers() -> list[dict]:
    raw = _run(["podman", "ps", "-a", "--format", "json"])
    if not raw:
        return []
    try:
        items = json.loads(raw)
    except json.JSONDecodeError:
        return []
    results = []
    for c in items:
        name = c.get("Names", c.get("Name", ["unknown"]))
        if isinstance(name, list):
            name = name[0] if name else "unknown"
        if name.startswith("haproxy"):
            continue
        health = ""
        if isinstance(c.get("Health"), dict):
            health = c["Health"].get("Status", "")
        elif isinstance(c.get("Health"), str):
            health = c["Health"]
        status = c.get("Status", c.get("State", ""))
        ports_raw = c.get("Ports", [])
        if isinstance(ports_raw, list):
            port_strs = []
            for p in ports_raw:
                if isinstance(p, dict):
                    host_ip = p.get("host_ip", "0.0.0.0")
                    host_port = p.get("host_port", "")
                    container_port = p.get("container_port", "")
                    proto = p.get("protocol", "tcp")
                    if host_port and container_port:
                        port_strs.append(f"{host_ip}:{host_port}->{container_port}/{proto}")
                elif isinstance(p, str):
                    port_strs.append(p)
            ports = ", ".join(port_strs)
        else:
            ports = str(ports_raw) if ports_raw else ""
        results.append({
            "name": name,
            "image": c.get("Image", ""),
            "status": status,
            "health": health,
            "ports": ports,
            "created": c.get("Created", c.get("CreatedAt", "")),
            "id": c.get("Id", "")[:12],
            "state": c.get("State", ""),
        })
    return results


def get_systemd_units() -> list[dict]:
    raw = _run(["systemctl", "list-units", "--type=service", "--no-pager", "--no-legend"])
    if not raw:
        return []
    units = []
    for line in raw.strip().splitlines():
        parts = line.split()
        if len(parts) >= 4:
            units.append({
                "name": parts[0],
                "load": parts[1],
                "active": parts[2],
                "sub": parts[3],
                "description": " ".join(parts[4:]),
            })
    return units


def get_host_metrics() -> dict:
    hostname = _run(["hostname"]).strip()

    uptime_secs = 0.0
    try:
        uptime_secs = float(Path("/proc/uptime").read_text().split()[0])
    except Exception:
        pass
    days = int(uptime_secs // 86400)
    hours = int((uptime_secs % 86400) // 3600)
    uptime_str = f"{days}d {hours}h" if days else f"{hours}h"

    load_avg = [0.0, 0.0, 0.0]
    try:
        parts = Path("/proc/loadavg").read_text().split()
        load_avg = [float(parts[0]), float(parts[1]), float(parts[2])]
    except Exception:
        pass

    cpu_percent = _get_cpu_percent()

    mem = {"total_gb": 0, "used_gb": 0, "available_gb": 0, "percent": 0}
    try:
        meminfo = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            if ":" in line:
                key, val = line.split(":", 1)
                meminfo[key.strip()] = int(val.strip().split()[0])
        total = meminfo.get("MemTotal", 0)
        available = meminfo.get("MemAvailable", 0)
        used = total - available
        mem = {
            "total_gb": round(total / 1048576, 1),
            "used_gb": round(used / 1048576, 1),
            "available_gb": round(available / 1048576, 1),
            "percent": round(used / total * 100, 1) if total else 0,
        }
    except Exception:
        pass

    disks = []
    df_out = _run(["df", "-h", "--output=target,size,used,avail,pcent", "-x", "tmpfs", "-x", "devtmpfs", "-x", "overlay"])
    for line in df_out.strip().splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 5:
            disks.append({
                "mount": parts[0],
                "total": parts[1],
                "used": parts[2],
                "available": parts[3],
                "percent": int(parts[4].rstrip("%")) if parts[4].rstrip("%").isdigit() else 0,
            })

    return {
        "hostname": hostname,
        "uptime": uptime_str,
        "uptime_seconds": uptime_secs,
        "cpu_percent": cpu_percent,
        "cpu_count": _get_cpu_count(),
        "load_avg": load_avg,
        "memory": mem,
        "disks": disks,
    }


_prev_cpu: tuple[float, float] | None = None
_prev_cpu_time: float = 0


def _get_cpu_percent() -> float:
    global _prev_cpu, _prev_cpu_time
    try:
        line = Path("/proc/stat").read_text().splitlines()[0]
        vals = [float(v) for v in line.split()[1:]]
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        total = sum(vals)
        now = time.monotonic()
        if _prev_cpu and (now - _prev_cpu_time) > 0.5:
            d_total = total - _prev_cpu[0]
            d_idle = idle - _prev_cpu[1]
            pct = ((d_total - d_idle) / d_total * 100) if d_total > 0 else 0
        else:
            pct = 0
        _prev_cpu = (total, idle)
        _prev_cpu_time = now
        return round(pct, 1)
    except Exception:
        return 0


def _get_cpu_count() -> int:
    try:
        return sum(1 for l in Path("/proc/stat").read_text().splitlines() if l.startswith("cpu") and l[3:4].isdigit())
    except Exception:
        return 1
