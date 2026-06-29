#!/usr/bin/env python3
"""Orchestration script to start both Cachy FastAPI backend and Flutter web frontend.

Starts the FastAPI backend using uvicorn from the virtual environment and launches
the Flutter web frontend on Chrome.
"""

import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional


def find_executable(name: str) -> Optional[str]:
    """Find the path to an executable in PATH.

    Args:
        name: The name of the executable to search for.

    Returns:
        The path string if found, otherwise None.
    """
    return shutil.which(name)


def run_app() -> int:
    """Start the Cachy backend and Flutter frontend subprocesses.

    Returns:
        Exit code (0 for clean shutdown, non-zero for error).
    """
    root_dir: Path = Path(__file__).resolve().parent
    backend_dir: Path = root_dir / "backend"
    frontend_dir: Path = root_dir / "app"

    venv_uvicorn: Path = backend_dir / ".venv" / "bin" / "uvicorn"
    if not venv_uvicorn.exists():
        print(f"Error: Virtualenv uvicorn not found at {venv_uvicorn}. Please set up the backend venv.")
        return 1

    flutter_bin: Optional[str] = find_executable("flutter")
    if flutter_bin is None:
        print("Error: 'flutter' executable not found in PATH.")
        return 1

    backend_cmd: List[str] = [
        str(venv_uvicorn),
        "app.main:app",
        "--reload",
        # Bind all interfaces so a phone on the same WiFi can reach the API after
        # LAN discovery (not just localhost). Local-testing only.
        "--host",
        "0.0.0.0",
        "--port",
        "8000",
    ]

    frontend_cmd: List[str] = [
        flutter_bin,
        "run",
        "-d",
        "chrome",
        "--dart-define=CACHY_API_BASE=http://localhost:8000",
    ]

    print("Starting Cachy Backend (port 8000)...")
    backend_proc: Optional[subprocess.Popen] = None
    frontend_proc: Optional[subprocess.Popen] = None

    try:
        backend_proc = subprocess.Popen(backend_cmd, cwd=backend_dir)
    except Exception as e:
        print(f"Failed to start backend subprocess: {e}")
        return 1

    time.sleep(2)

    print("Starting Cachy Flutter Frontend on Chrome...")
    try:
        frontend_proc = subprocess.Popen(frontend_cmd, cwd=frontend_dir)
    except Exception as e:
        print(f"Failed to start frontend subprocess: {e}")
        if backend_proc.poll() is None:
            backend_proc.terminate()
        return 1

    try:
        frontend_proc.wait()
    except KeyboardInterrupt:
        print("\nReceived keyboard interrupt. Shutting down servers...")
    except Exception as e:
        print(f"Unexpected error during execution: {e}")
    finally:
        if frontend_proc and frontend_proc.poll() is None:
            frontend_proc.terminate()
        if backend_proc and backend_proc.poll() is None:
            backend_proc.terminate()
            try:
                backend_proc.wait(timeout=5)
            except subprocess.TimeoutExpired as e:
                print(f"Backend did not terminate gracefully, killing process: {e}")
                backend_proc.kill()

    print("Cachy shutdown complete.")
    return 0


if __name__ == "__main__":
    sys.exit(run_app())
