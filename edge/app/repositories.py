import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Episode


class EpisodeRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def get_by_idempotency_key(self, key: str) -> Episode | None:
        return self._session.scalar(
            select(Episode).where(Episode.idempotency_key == key)
        )

    def list(self) -> list[Episode]:
        return list(
            self._session.scalars(
                select(Episode).order_by(Episode.created_at.desc())
            )
        )

    def get(self, episode_id: uuid.UUID) -> Episode | None:
        return self._session.get(Episode, episode_id)

    def add(self, episode: Episode) -> Episode:
        self._session.add(episode)
        self._session.commit()
        self._session.refresh(episode)
        return episode

    def rollback(self) -> None:
        self._session.rollback()

    def save(self, episode: Episode) -> Episode:
        self._session.add(episode)
        self._session.commit()
        self._session.refresh(episode)
        return episode

    def delete(self, episode: Episode) -> None:
        self._session.delete(episode)
        self._session.commit()
