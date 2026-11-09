import importlib
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Any, Protocol, runtime_checkable


class GateDecision(StrEnum):
    ACCEPT = "accepted"
    REJECT = "rejected"
    REVIEW = "review"


@dataclass(frozen=True)
class GateResult:
    decision: GateDecision
    reason_code: str
    reason: str
    plugin_version: str
    scores: dict[str, float]
    review_intervals: list[dict[str, Any]]


@dataclass(frozen=True)
class GateInput:
    episode_id: str
    path: Path
    size_bytes: int
    checksum_sha256: str
    manifest: dict[str, Any]


@runtime_checkable
class BuyerGate(Protocol):
    version: str

    def evaluate(self, episode: GateInput) -> GateResult: ...


class BasicBuyerGate:
    version = "basic-size-gate-v1"

    def __init__(self, minimum_size_bytes: int = 1024) -> None:
        self._minimum_size_bytes = minimum_size_bytes

    def evaluate(self, episode: GateInput) -> GateResult:
        if episode.size_bytes < self._minimum_size_bytes:
            return GateResult(
                decision=GateDecision.REJECT,
                reason_code="file_too_small",
                reason=(
                    f"Episode is smaller than "
                    f"{self._minimum_size_bytes} bytes."
                ),
                plugin_version=self.version,
                scores={"file_size": 0.0},
                review_intervals=[],
            )

        return GateResult(
            decision=GateDecision.REVIEW,
            reason_code="basic_checks_passed",
            reason="Episode passed basic checks and is ready for buyer review.",
            plugin_version=self.version,
            scores={"file_size": 1.0},
            review_intervals=[],
        )


def load_buyer_gate(
    dotted_path: str | None,
    *,
    minimum_size_bytes: int,
) -> BuyerGate:
    if not dotted_path:
        return BasicBuyerGate(minimum_size_bytes)

    module_name, separator, attribute_name = dotted_path.rpartition(".")
    if not separator:
        raise ValueError(
            "BUYER_GATE_PLUGIN must be a dotted class path, "
            "for example package.module.CustomGate."
        )

    module = importlib.import_module(module_name)
    gate_class = getattr(module, attribute_name)
    gate = gate_class()
    if not isinstance(gate, BuyerGate):
        raise TypeError(
            f"{dotted_path} does not implement the BuyerGate contract."
        )
    return gate
