# Phase 2 — Privacy pipeline

## Goal

Convert camera frames into a finalized MP4 that contains only sanitized frames.

## Work

- Detect faces with Vision and track them between full detections.
- Attach timestamps, confidence, orientation, and expiry to every face track.
- Render padded privacy masks with Core Image and a reusable Metal-backed context.
- Fail closed: obscure the whole frame or drop it when masks are stale or processing fails.
- Give sanitized buffers a distinct type that is the only input accepted by the writer.
- Encode finalized H.264 segments with AVAssetWriter.
- Store segments in protected, no-backup application storage.
- Disable audio and remove unnecessary container metadata.
- Validate the finalized output before it can enter the upload queue.

## Done when

- No raw frame path can reach AVAssetWriter.
- Rapid face entry, occlusion, rotation, and low-light tests do not produce unmasked output.
- Interrupted or failed recordings are never marked uploadable.
- Finalized sanitized videos play correctly and temporary artifacts are cleaned up.
