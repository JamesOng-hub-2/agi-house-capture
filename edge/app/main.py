import os
from pathlib import Path
from typing import Annotated
from uuid import uuid4

from fastapi import FastAPI, File, Form, Request, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

from .gate import evaluate_episode

APP_DIR = Path(__file__).resolve().parent
EDGE_DIR = APP_DIR.parent
EPISODE_DIR = EDGE_DIR / os.getenv("EPISODE_DIR", "data/episodes")
MIN_EPISODE_BYTES = int(os.getenv("MIN_EPISODE_BYTES", "1024"))

app = FastAPI(title="AGI House Capture Edge", version="0.1.0")
templates = Jinja2Templates(directory=APP_DIR / "templates")


class Task(BaseModel):
    id: str
    title: str
    instructions: str


class Episode(BaseModel):
    id: str
    task_id: str
    filename: str
    size_bytes: int
    decision: str
    reason: str


TASKS = [
    Task(
        id="pick-and-place",
        title="Pick and place",
        instructions="Pick up the object and place it in the marked target area.",
    )
]
episodes: list[Episode] = []


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/tasks")
def list_tasks() -> list[Task]:
    return TASKS


@app.get("/episodes")
def list_episodes() -> list[Episode]:
    return episodes


@app.post("/episodes")
async def create_episode(
    task_id: Annotated[str, Form()],
    video: Annotated[UploadFile, File()],
) -> Episode:
    episode_id = str(uuid4())
    suffix = Path(video.filename or "episode.mp4").suffix or ".mp4"
    destination = EPISODE_DIR / f"{episode_id}{suffix}"
    destination.parent.mkdir(parents=True, exist_ok=True)

    contents = await video.read()
    destination.write_bytes(contents)
    result = evaluate_episode(
        size_bytes=len(contents),
        minimum_size_bytes=MIN_EPISODE_BYTES,
    )

    episode = Episode(
        id=episode_id,
        task_id=task_id,
        filename=destination.name,
        size_bytes=len(contents),
        decision=result.decision,
        reason=result.reason,
    )
    episodes.append(episode)
    return episode


@app.get("/review", response_class=HTMLResponse)
def review(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="review.html",
        context={"episodes": episodes},
    )
