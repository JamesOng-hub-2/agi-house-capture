from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

EDGE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=EDGE_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: str = (
        "postgresql+psycopg://agi_house:agi_house@localhost:5432/agi_house_capture"
    )
    episode_dir: Path = Path("data/episodes")
    min_episode_bytes: int = 1024
    max_episode_bytes: int = 500 * 1024 * 1024

    @property
    def resolved_episode_dir(self) -> Path:
        if self.episode_dir.is_absolute():
            return self.episode_dir
        return EDGE_DIR / self.episode_dir


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
