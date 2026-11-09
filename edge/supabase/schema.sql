create table if not exists public.episodes (
    id uuid primary key,
    task_id text not null,
    checksum_sha256 text not null unique,
    decision text not null check (decision = 'accepted'),
    gate_version text not null,
    manifest jsonb not null,
    storage_path text not null unique,
    created_at timestamptz not null default now()
);

insert into storage.buckets (id, name, public)
values ('episodes', 'episodes', false)
on conflict (id) do nothing;
