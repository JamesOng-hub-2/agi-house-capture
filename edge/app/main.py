import hashlib
import json
import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated
from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, ValidationError

from .gate import evaluate_episode
from .store import EpisodeStore, StoredEpisode

APP_DIR = Path(__file__).resolve().parent
EDGE_DIR = APP_DIR.parent
EPISODE_DIR = EDGE_DIR / os.getenv("EPISODE_DIR", "data/episodes")
DATABASE_PATH = EDGE_DIR / os.getenv("DATABASE_PATH", "data/episodes.sqlite3")
MIN_EPISODE_BYTES = int(os.getenv("MIN_EPISODE_BYTES", "1024"))
MAX_EPISODE_BYTES = int(os.getenv("MAX_EPISODE_BYTES", str(500 * 1024 * 1024)))

app = FastAPI(title="AGI House Capture Edge", version="0.1.0")
templates = Jinja2Templates(directory=APP_DIR / "templates")
store = EpisodeStore(DATABASE_PATH)


class Task(BaseModel):
    id: str
    title: str
    instructions: str


class EpisodeManifest(BaseModel):
    schema_version: str
    episode_id: str
    task_id: str
    captured_at: str
    duration_seconds: float
    width: int
    height: int
    nominal_frame_rate: float
    anonymizer_version: str


class Episode(BaseModel):
    id: str
    task_id: str
    filename: str
    size_bytes: int
    checksum_sha256: str
    decision: str
    reason: str
    created_at: str
    manifest: EpisodeManifest


TASKS = [
    Task(
        id="pick-and-place",
        title="Pick and place",
        instructions="Pick up the object and place it in the marked target area.",
    )
]
@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/tasks")
def list_tasks() -> list[Task]:
    return TASKS


@app.get("/episodes")
def list_episodes() -> list[Episode]:
    return [Episode.model_validate(episode.as_dict()) for episode in store.list()]


@app.post("/episodes")
async def create_episode(
    idempotency_key: Annotated[str, Form(min_length=1, max_length=128)],
    checksum_sha256: Annotated[str, Form(pattern=r"^[0-9a-f]{64}$")],
    manifest: Annotated[str, Form()],
    video: Annotated[UploadFile, File()],
) -> Episode:
    existing = store.get_by_idempotency_key(idempotency_key)
    if existing:
        if existing.checksum_sha256 != checksum_sha256:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Idempotency key already belongs to different content.",
            )
        return Episode.model_validate(existing.as_dict())

    try:
        parsed_manifest = EpisodeManifest.model_validate_json(manifest)
    except ValidationError as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=json.loads(error.json()),
        ) from error

    if parsed_manifest.episode_id != idempotency_key:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Manifest episode_id must match the idempotency key.",
        )

    episode_id = str(uuid4())
    EPISODE_DIR.mkdir(parents=True, exist_ok=True)
    staging = EPISODE_DIR / f".{episode_id}.uploading"
    destination = EPISODE_DIR / f"{episode_id}.mp4"

    digest = hashlib.sha256()
    size_bytes = 0
    try:
        with staging.open("wb") as output:
            while chunk := await video.read(1024 * 1024):
                size_bytes += len(chunk)
                if size_bytes > MAX_EPISODE_BYTES:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="Episode exceeds the configured size limit.",
                    )
                digest.update(chunk)
                output.write(chunk)

        measured_checksum = digest.hexdigest()
        if measured_checksum != checksum_sha256:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Episode checksum does not match the uploaded file.",
            )

        result = evaluate_episode(
            size_bytes=size_bytes,
            minimum_size_bytes=MIN_EPISODE_BYTES,
        )
        staging.replace(destination)

        stored = StoredEpisode(
            id=episode_id,
            idempotency_key=idempotency_key,
            task_id=parsed_manifest.task_id,
            filename=destination.name,
            size_bytes=size_bytes,
            checksum_sha256=measured_checksum,
            decision=result.decision,
            reason=result.reason,
            created_at=datetime.now(UTC).isoformat(),
            manifest=parsed_manifest.model_dump(),
        )
        store.insert(stored)
        return Episode.model_validate(stored.as_dict())
    except Exception:
        staging.unlink(missing_ok=True)
        if not store.get_by_idempotency_key(idempotency_key):
            destination.unlink(missing_ok=True)
        raise


@app.get("/review", response_class=HTMLResponse)
def review(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="review.html",
        context={"episodes": store.list()},
    )
