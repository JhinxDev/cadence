"""LRU disk cache manager for resolved discovery audio streams."""

import time
from pathlib import Path


def enforce_cache_limit(cache_dir: Path, max_mb: int) -> None:
    """Evict least-recently-used cached audio files when disk usage exceeds max_mb."""
    if max_mb <= 0 or not cache_dir.exists():
        return
    max_bytes = max_mb * 1024 * 1024
    files: list[tuple[float, int, Path]] = []
    total = 0
    for path in cache_dir.iterdir():
        if not path.is_file():
            continue
        stat = path.stat()
        total += stat.st_size
        files.append((stat.st_atime or stat.st_mtime, stat.st_size, path))

    if total <= max_bytes:
        return

    files.sort(key=lambda item: item[0])
    for _, size, path in files:
        if total <= max_bytes:
            break
        try:
            path.unlink()
            total -= size
        except OSError:
            continue


def touch_cache_file(path: Path) -> None:
    """Bump access/modification time so LRU keeps hot tracks."""
    try:
        now = time.time()
        path.touch(exist_ok=True)
        import os

        os.utime(path, (now, now))
    except OSError:
        pass
