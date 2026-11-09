from dataclasses import dataclass
from pathlib import Path

from supabase import Client, create_client

from .config import settings
from .models import Episode


@dataclass(frozen=True)
class CloudUploadResult:
    status: str
    path: str | None


class SupabaseUploader:
    def __init__(self) -> None:
        self._client: Client | None = None

    @property
    def configured(self) -> bool:
        return settings.supabase_enabled

    def upload(self, episode: Episode, file_path: Path) -> CloudUploadResult:
        if not self.configured:
            return CloudUploadResult(status="not_configured", path=None)
        if episode.decision != "accepted":
            return CloudUploadResult(status="not_approved", path=None)

        cloud_path = f"approved/{episode.checksum_sha256}.mp4"
        client = self._get_client()
        client.storage.from_(settings.supabase_storage_bucket).upload(
            path=cloud_path,
            file=file_path,
            file_options={
                "content-type": "video/mp4",
                "upsert": "true",
            },
        )
        client.table(settings.supabase_metadata_table).upsert(
            {
                "id": str(episode.id),
                "task_id": episode.task_id,
                "checksum_sha256": episode.checksum_sha256,
                "decision": episode.decision,
                "gate_version": episode.gate_version,
                "manifest": episode.manifest,
                "storage_path": cloud_path,
            },
            on_conflict="id",
        ).execute()
        return CloudUploadResult(status="uploaded", path=cloud_path)

    def delete(self, episode: Episode) -> None:
        if not self.configured:
            if episode.cloud_path:
                raise RuntimeError(
                    "Supabase credentials are required to delete the cloud copy."
                )
            return

        client = self._get_client()
        if episode.cloud_path:
            client.storage.from_(settings.supabase_storage_bucket).remove(
                [episode.cloud_path]
            )
        client.table(settings.supabase_metadata_table).delete().eq(
            "id", str(episode.id)
        ).execute()

    def _get_client(self) -> Client:
        if self._client is None:
            self._client = create_client(
                settings.supabase_url,
                settings.supabase_service_role_key,
            )
        return self._client


supabase_uploader = SupabaseUploader()
