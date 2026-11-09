import hashlib
import json
from contextlib import asynccontextmanager
from datetime import UTC, datetime
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
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, ConfigDict, ValidationError
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .cloud import supabase_uploader
from .config import settings
from .database import SessionLocal, get_session
from .gate import GateInput, load_buyer_gate
from .maintenance import (
    cleanup_orphaned_episodes,
    cleanup_staging_files,
    current_storage_bytes,
)
from .models import Episode as EpisodeRecord
from .repositories import EpisodeRepository

APP_DIR = Path(__file__).resolve().parent


@asynccontextmanager
async def lifespan(_: FastAPI):
    cleanup_staging_files()
    with SessionLocal() as session:
        repository = EpisodeRepository(session)
        cleanup_orphaned_episodes(
            {episode.filename for episode in repository.list()}
        )
    yield


app = FastAPI(
    title="AGI House Capture Edge",
    version="0.1.0",
    lifespan=lifespan,
)
templates = Jinja2Templates(directory=APP_DIR / "templates")
buyer_gate = load_buyer_gate(
    settings.buyer_gate_plugin,
    minimum_size_bytes=settings.min_episode_bytes,
)


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
    gate_version: str
    gate_details: dict
    cloud_status: str
    cloud_path: str | None
    uploaded_at: datetime | None
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
    existing_storage_bytes = current_storage_bytes()
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
                if (
                    existing_storage_bytes + size_bytes
                    > settings.max_edge_storage_bytes
                ):
                    raise HTTPException(
                        status_code=status.HTTP_507_INSUFFICIENT_STORAGE,
                        detail="Edge episode storage quota is full.",
                    )
                digest.update(chunk)
                output.write(chunk)

        measured_checksum = digest.hexdigest()
        if measured_checksum != checksum_sha256:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Episode checksum does not match the uploaded file.",
            )

        result = buyer_gate.evaluate(
            GateInput(
                episode_id=str(episode_id),
                path=staging,
                size_bytes=size_bytes,
                checksum_sha256=measured_checksum,
                manifest=parsed_manifest.model_dump(),
            )
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
            gate_version=result.plugin_version,
            gate_details={
                "reason_code": result.reason_code,
                "scores": result.scores,
                "review_intervals": result.review_intervals,
            },
            cloud_status="not_approved",
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
        context={
            "episodes": repository.list(),
            "supabase_enabled": settings.supabase_enabled,
        },
    )


@app.get("/episodes/{episode_id}/video")
def episode_video(
    episode_id: UUID,
    session: Annotated[Session, Depends(get_session)],
) -> FileResponse:
    repository = EpisodeRepository(session)
    episode = repository.get(episode_id)
    if not episode:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    path = settings.resolved_episode_dir / episode.filename
    if not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Episode video is missing.",
        )
    return FileResponse(path, media_type="video/mp4", filename=episode.filename)


@app.post("/episodes/{episode_id}/decision")
def update_episode_decision(
    episode_id: UUID,
    decision: Annotated[
        str,
        Form(pattern=r"^(accepted|rejected|review)$"),
    ],
    reason: Annotated[str, Form(min_length=1, max_length=1000)],
    session: Annotated[Session, Depends(get_session)],
) -> RedirectResponse:
    repository = EpisodeRepository(session)
    episode = repository.get(episode_id)
    if not episode:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    episode.decision = decision
    episode.reason = reason
    episode.gate_version = "human-review-v1"
    episode.gate_details = {
        **episode.gate_details,
        "human_reviewed_at": datetime.now(UTC).isoformat(),
    }

    if decision == "accepted":
        episode.cloud_status = "uploading"
        repository.save(episode)
        path = settings.resolved_episode_dir / episode.filename
        try:
            cloud_result = supabase_uploader.upload(episode, path)
            episode.cloud_status = cloud_result.status
            episode.cloud_path = cloud_result.path
            episode.uploaded_at = (
                datetime.now(UTC)
                if cloud_result.status == "uploaded"
                else None
            )
        except Exception as error:
            episode.cloud_status = "failed"
            episode.gate_details = {
                **episode.gate_details,
                "cloud_error": str(error),
            }
    else:
        if episode.cloud_path:
            supabase_uploader.delete(episode)
        episode.cloud_status = "not_approved"
        episode.cloud_path = None
        episode.uploaded_at = None

    repository.save(episode)
    return RedirectResponse("/review", status_code=status.HTTP_303_SEE_OTHER)


@app.post("/episodes/{episode_id}/delete")
def delete_episode(
    episode_id: UUID,
    session: Annotated[Session, Depends(get_session)],
) -> RedirectResponse:
    repository = EpisodeRepository(session)
    episode = repository.get(episode_id)
    if not episode:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    supabase_uploader.delete(episode)
    path = settings.resolved_episode_dir / episode.filename
    path.unlink(missing_ok=True)
    repository.delete(episode)
    return RedirectResponse("/review", status_code=status.HTTP_303_SEE_OTHER)
