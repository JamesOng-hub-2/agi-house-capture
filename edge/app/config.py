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
    max_edge_storage_bytes: int = 50 * 1024 * 1024 * 1024
    upload_staging_max_age_minutes: int = 60
    buyer_gate_plugin: str | None = None

    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_storage_bucket: str = "episodes"
    supabase_metadata_table: str = "episodes"

    @property
    def resolved_episode_dir(self) -> Path:
        if self.episode_dir.is_absolute():
            return self.episode_dir
        return EDGE_DIR / self.episode_dir

    @property
    def supabase_enabled(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_role_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
