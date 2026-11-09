import json
import sqlite3
from dataclasses import asdict, dataclass
from pathlib import Path
from threading import Lock


@dataclass(frozen=True)
class StoredEpisode:
    id: str
    idempotency_key: str
    task_id: str
    filename: str
    size_bytes: int
    checksum_sha256: str
    decision: str
    reason: str
    created_at: str
    manifest: dict

    def as_dict(self) -> dict:
        return asdict(self)


class EpisodeStore:
    def __init__(self, database_path: Path) -> None:
        database_path.parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(database_path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._lock = Lock()
        self._connection.execute(
            """
            CREATE TABLE IF NOT EXISTS episodes (
                id TEXT PRIMARY KEY,
                idempotency_key TEXT NOT NULL UNIQUE,
                task_id TEXT NOT NULL,
                filename TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                checksum_sha256 TEXT NOT NULL,
                decision TEXT NOT NULL,
                reason TEXT NOT NULL,
                created_at TEXT NOT NULL,
                manifest_json TEXT NOT NULL
            )
            """
        )
        self._connection.commit()

    def get_by_idempotency_key(self, key: str) -> StoredEpisode | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT * FROM episodes WHERE idempotency_key = ?",
                (key,),
            ).fetchone()
        return self._from_row(row) if row else None

    def insert(self, episode: StoredEpisode) -> StoredEpisode:
        with self._lock:
            self._connection.execute(
                """
                INSERT INTO episodes (
                    id, idempotency_key, task_id, filename, size_bytes,
                    checksum_sha256, decision, reason, created_at, manifest_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    episode.id,
                    episode.idempotency_key,
                    episode.task_id,
                    episode.filename,
                    episode.size_bytes,
                    episode.checksum_sha256,
                    episode.decision,
                    episode.reason,
                    episode.created_at,
                    json.dumps(episode.manifest, separators=(",", ":"), sort_keys=True),
                ),
            )
            self._connection.commit()
        return episode

    def list(self) -> list[StoredEpisode]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT * FROM episodes ORDER BY created_at DESC"
            ).fetchall()
        return [self._from_row(row) for row in rows]

    @staticmethod
    def _from_row(row: sqlite3.Row) -> StoredEpisode:
        return StoredEpisode(
            id=row["id"],
            idempotency_key=row["idempotency_key"],
            task_id=row["task_id"],
            filename=row["filename"],
            size_bytes=row["size_bytes"],
            checksum_sha256=row["checksum_sha256"],
            decision=row["decision"],
            reason=row["reason"],
            created_at=row["created_at"],
            manifest=json.loads(row["manifest_json"]),
        )
