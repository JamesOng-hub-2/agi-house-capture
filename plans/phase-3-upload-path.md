# Phase 3 — Upload path

## Goal

Reliably deliver a validated sanitized episode to the laptop and display its gate result on the phone.

## Work

- Define the versioned episode manifest and API models.
- Include task ID, capture timing, media properties, anonymizer version, and checksum.
- Persist upload records independently from in-memory UI state.
- Upload finalized files with URLSession multipart requests.
- Add idempotency keys and checksum verification.
- Retry safely across network loss and app restarts.
- Show queued, uploading, accepted, rejected, review, and failed states.
- Delete the phone copy only after a verified laptop acknowledgement.
- Update the edge endpoint to stream uploads rather than loading entire videos into memory.

## Done when

- A phone-recorded sanitized episode appears on the laptop review page.
- Disconnecting Wi-Fi produces a queued retry rather than data loss.
- Repeated requests cannot create duplicate episodes.
- Successful uploads are removed from phone storage.
