# Build plan

The project is split into four phases. Complete and validate each phase on a physical iPhone before moving to the next.

1. [Camera foundation](phase-1-camera-foundation.md)
2. [Privacy pipeline](phase-2-privacy-pipeline.md)
3. [Upload path](phase-3-upload-path.md)
4. [Hardening](phase-4-hardening.md)

## Guiding rules

- Raw camera frames must never be written to disk or transmitted.
- Privacy failures must fail closed by obscuring or dropping affected frames.
- Keep every real-time queue bounded.
- Build one testable end-to-end slice at a time.
