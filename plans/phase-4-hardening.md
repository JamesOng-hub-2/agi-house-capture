# Phase 4 — Hardening

## Goal

Make the system resilient enough for repeated collection sessions and controlled cloud delivery.

## Work

- Adapt capture quality based on thermal and system pressure.
- Recover safely from camera, encoder, storage, and application interruptions.
- Add independent residual-face and media-integrity checks.
- Define the sandboxed, versioned buyer-gate plugin interface.
- Add structured reason codes and human-review intervals.
- Upload only approved asset hashes to Supabase.
- Enforce retention, deletion, storage quotas, and orphan cleanup.
- Add adversarial privacy, lifecycle, networking, and disk-pressure tests.
- Run device soak tests and measure dropped frames, temperature, memory, and battery use.

## Done when

- Long capture sessions degrade safely rather than leaking frames or crashing.
- Gate decisions are reproducible for the same asset and plugin version.
- Rejected or privacy-invalid episodes cannot reach cloud storage.
- Retention and deletion behavior is verified across the phone, laptop, and cloud.
