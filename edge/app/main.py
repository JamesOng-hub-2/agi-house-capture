import hashlib
import json
from datetime import datetime
from pathlib import Path
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, ConfigDict, ValidationError
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .config import settings
from .database import get_session
from .gate import evaluate_episode
from .models import Episode as EpisodeRecord
from .repositories import EpisodeRepository

APP_DIR = Path(__file__).resolve().parent

app = FastAPI(title="AGI House Capture Edge", version="0.1.0")
templates = Jinja2Templates(directory=APP_DIR / "templates")


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


class EpisodeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    task_id: str
    filename: str
    size_bytes: int
    checksum_sha256: str
    decision: str
    reason: str
    created_at: datetime
    manifest: EpisodeManifest


TASKS = [
    Task(
        id="pick-and-place",
        title="Pick and place",
        instructions="Pick up the object and place it in the marked target area.",
    )
]


@app.get("/health")
def health(
    session: Annotated[Session, Depends(get_session)],
) -> dict[str, str]:
    session.execute(text("SELECT 1"))
    return {"status": "ok", "database": "postgresql"}


@app.get("/tasks")
def list_tasks() -> list[Task]:
    return TASKS


@app.get("/episodes")
def list_episodes(
    session: Annotated[Session, Depends(get_session)],
) -> list[EpisodeResponse]:
    repository = EpisodeRepository(session)
    return [
        EpisodeResponse.model_validate(episode)
        for episode in repository.list()
    ]


@app.post("/episodes")
async def create_episode(
    idempotency_key: Annotated[str, Form(min_length=1, max_length=128)],
    checksum_sha256: Annotated[str, Form(pattern=r"^[0-9a-f]{64}$")],
    manifest: Annotated[str, Form()],
    video: Annotated[UploadFile, File()],
    session: Annotated[Session, Depends(get_session)],
) -> EpisodeResponse:
    repository = EpisodeRepository(session)
    existing = repository.get_by_idempotency_key(idempotency_key)
    if existing:
        if existing.checksum_sha256 != checksum_sha256:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Idempotency key already belongs to different content.",
            )
        return EpisodeResponse.model_validate(existing)

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

    episode_id = uuid4()
    episode_directory = settings.resolved_episode_dir
    episode_directory.mkdir(parents=True, exist_ok=True)
    staging = episode_directory / f".{episode_id}.uploading"
    destination = episode_directory / f"{episode_id}.mp4"

    digest = hashlib.sha256()
    size_bytes = 0
    committed = False
    try:
        with staging.open("wb") as output:
            while chunk := await video.read(1024 * 1024):
                size_bytes += len(chunk)
                if size_bytes > settings.max_episode_bytes:
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
            minimum_size_bytes=settings.min_episode_bytes,
        )
        staging.replace(destination)

        stored = EpisodeRecord(
            id=episode_id,
            idempotency_key=idempotency_key,
            task_id=parsed_manifest.task_id,
            filename=destination.name,
            size_bytes=size_bytes,
            checksum_sha256=measured_checksum,
            decision=result.decision,
            reason=result.reason,
            manifest=parsed_manifest.model_dump(),
        )
        try:
            repository.add(stored)
            committed = True
        except IntegrityError:
            repository.rollback()
            duplicate = repository.get_by_idempotency_key(idempotency_key)
            if duplicate and duplicate.checksum_sha256 == checksum_sha256:
                destination.unlink(missing_ok=True)
                return EpisodeResponse.model_validate(duplicate)
            raise

        return EpisodeResponse.model_validate(stored)
    except Exception:
        staging.unlink(missing_ok=True)
        if not committed:
            destination.unlink(missing_ok=True)
        raise


@app.get("/review", response_class=HTMLResponse)
def review(
    request: Request,
    session: Annotated[Session, Depends(get_session)],
) -> HTMLResponse:
    repository = EpisodeRepository(session)
    return templates.TemplateResponse(
        request=request,
        name="review.html",
        context={"episodes": repository.list()},
    )
