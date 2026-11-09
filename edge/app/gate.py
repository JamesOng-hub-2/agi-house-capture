from dataclasses import dataclass
from enum import StrEnum


class GateDecision(StrEnum):
    ACCEPT = "accepted"
    REJECT = "rejected"
    REVIEW = "review"


@dataclass(frozen=True)
class GateResult:
    decision: GateDecision
    reason: str


def evaluate_episode(*, size_bytes: int, minimum_size_bytes: int) -> GateResult:
    """Apply the initial deterministic buyer gate.

    More expensive local or cloud checks can be added after these cheap checks.
    """
    if size_bytes < minimum_size_bytes:
        return GateResult(
            decision=GateDecision.REJECT,
            reason=f"Episode is smaller than {minimum_size_bytes} bytes.",
        )

    return GateResult(
        decision=GateDecision.REVIEW,
        reason="Episode passed basic checks and is ready for buyer review.",
    )
