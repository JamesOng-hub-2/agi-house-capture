# iOS architecture

```mermaid
flowchart LR
    UI["SwiftUI screen<br/>Preview and status"]
    VM["Capture coordinator<br/>State machine"]
    Camera["Camera service<br/>AVFoundation"]
    Memory["Raw frames<br/>Memory only"]
    Privacy["Anonymizer<br/>Vision + Core Image"]
    Encoder["Video encoder<br/>AVAssetWriter"]
    Disk[("Sanitized MP4<br/>Temporary disk")]
    Validator["Privacy validator<br/>Residual face scan"]
    Queue["Upload queue<br/>Metadata + retries"]
    Client["Edge client<br/>URLSession"]
    Laptop["Laptop edge server<br/>Buyer gate"]

    UI <--> VM
    VM --> Camera
    Camera --> Memory
    Memory --> Privacy
    Privacy --> Encoder
    Encoder --> Disk
    Disk --> Validator
    Validator -->|"Pass"| Queue
    Validator -->|"Fail: delete"| VM
    VM --> Queue
    Queue --> Client
    Client --> Laptop
    Laptop -->|"Gate result"| VM
```

## Data boundaries

- Raw camera frames exist briefly in memory and are never uploaded or written to disk.
- Face detection and tracking run on-device before each frame reaches the encoder.
- Only the anonymized MP4 is stored temporarily on the phone.
- Finalized videos are independently sampled for residual faces before upload.
- The upload queue stores the file location, task metadata, and retry state.
- Successful uploads are deleted from the phone after the laptop confirms receipt.
- Thermal and camera-pressure signals reduce capture from 30 to 24 or 15 fps without weakening privacy.
