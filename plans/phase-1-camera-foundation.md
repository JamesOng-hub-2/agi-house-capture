# Phase 1 — Camera foundation

## Goal

Run a stable 720p/30 camera preview on a physical iPhone with explicit permissions, lifecycle state, and bounded frame handling.

## Work

- Add camera and local-network usage descriptions.
- Build the capture state machine: idle, requesting permission, configuring, previewing, interrupted, and failed.
- Configure the rear camera with AVFoundation at 1280×720 and 30 fps.
- Display the preview in SwiftUI.
- Deliver frames through a dedicated serial queue.
- Bound in-flight application-owned frames and drop excess frames.
- Record frame-drop, memory, and capture-error diagnostics without storing image data.
- Handle camera denial, backgrounding, calls, and media-service resets.

## Done when

- The preview runs for 10 minutes on the target iPhone.
- Memory remains bounded and the UI stays responsive.
- Backgrounding and returning does not crash or duplicate the capture session.
- No camera frame is written to disk or sent over the network.
