from datetime import UTC, datetime, timedelta
from pathlib import Path

from .config import settings


def cleanup_staging_files() -> int:
    directory = settings.resolved_episode_dir
    if not directory.exists():
        return 0

    cutoff = datetime.now(UTC) - timedelta(
        minutes=settings.upload_staging_max_age_minutes
    )
    removed = 0
    for path in directory.glob(".*.uploading"):
        modified = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
        if modified < cutoff:
            path.unlink(missing_ok=True)
            removed += 1
    return removed


def cleanup_orphaned_episodes(referenced_filenames: set[str]) -> int:
    directory = settings.resolved_episode_dir
    if not directory.exists():
        return 0

    removed = 0
    for path in directory.glob("*.mp4"):
        if path.name not in referenced_filenames:
            path.unlink(missing_ok=True)
            removed += 1
    return removed


def current_storage_bytes() -> int:
    directory = settings.resolved_episode_dir
    if not directory.exists():
        return 0
    return sum(path.stat().st_size for path in directory.glob("*.mp4"))
