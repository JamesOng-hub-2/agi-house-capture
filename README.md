# AGI House Capture

A privacy-first system for collecting useful egocentric robot-training data with devices contributors already own.

The iPhone records task episodes and anonymizes sensitive visual data on-device. A buyer-controlled module on the contributor's laptop evaluates each episode locally. Only approved, anonymized files are eligible for cloud upload.

## Architecture

- **iPhone (`ios/`)** — Captures frames, blurs faces, detects hand poses, shows coaching prompts, queues episodes offline, and sends them to the laptop.
- **Laptop edge server (`edge/`)** — Exposes the task and episode APIs, applies buyer gate rules, hosts the review page, and manages upload and optional model-escalation queues. API keys stay here.
- **Cloud** — Supabase storage and metadata only. No application code runs in the cloud.

## MVP scope

### Phone

- Record egocentric task episodes at 720p/30 fps, adapting to 24 or 15 fps under device pressure.
- Blur faces before data leaves the phone.
- Detect hand poses and provide capture-quality prompts.
- Send episodes to the edge server over the local network.
- Queue failed uploads and show connection, privacy, and upload status.

### Edge

- `GET /tasks` — Return the current capture task.
- `POST /episodes` — Accept an anonymized episode and return its gate result.
- `GET /episodes` — List received episodes and their status.
- `/review` — Review accepted, rejected, and uncertain episodes.
- Keep buyer rules and third-party API keys off the phone.

### Cloud

- Store approved video files in a Supabase bucket.
- Store episode metadata in a Supabase table.
- Optionally use Claude or Gemini for uncertain clips, with credentials held by the edge server.

## Privacy boundary

Raw capture data should not leave the phone. The laptop is a separate trust boundary because it runs buyer-controlled code; sending raw footage there would expose contributors' personal data to the buyer and increase consent, breach, and regulatory risk. Anonymizing on the contributor-controlled phone keeps raw data under the contributor's control.

The laptop receives anonymized episodes, independently checks that anonymization succeeded, runs the buyer's gate locally, and uploads only approved data. This is an enforced product policy rather than an assumption: episodes that still contain detectable personal information must be rejected. Secrets belong in `edge/.env`, which is excluded from Git.

## Build order

Detailed implementation plans live in [`plans/`](plans/README.md).

1. Set up the Python environment, local network, model download, and Supabase resources.
2. Build the edge server and gate rules; finish when an episode request returns a gate result.
3. Build the iPhone capture, anonymization, hand-pose, and upload flow.
4. Add the review page and Supabase upload.
5. Add the offline queue and status indicators.
6. Rehearse the demo and freeze the code.

If time is short, cut captions first, then cloud escalation, then text blurring.

## Local setup

### Edge server

```bash
cd edge
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
docker compose up -d
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --env-file .env
```

Open `http://localhost:8000/review`.

Episode metadata and gate results are stored in PostgreSQL through SQLAlchemy.
Schema changes are managed with Alembic migrations.

Optional Phase 4 settings in `edge/.env`:

- `BUYER_GATE_PLUGIN` selects a versioned buyer gate by dotted Python path.
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_BUCKET` enable approved-only cloud upload.
- Apply `edge/supabase/schema.sql` in Supabase before enabling cloud upload. Keep the service-role key on the laptop only.

### iOS app

Open `ios/AGIHouseCapture.xcodeproj` in Xcode, choose a signing team, and run on an iPhone.
