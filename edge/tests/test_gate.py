import tempfile
import unittest
from pathlib import Path

from app.gate import BasicBuyerGate, GateDecision, GateInput


class BasicBuyerGateTests(unittest.TestCase):
    def make_input(self, *, size_bytes: int) -> GateInput:
        return GateInput(
            episode_id="test",
            path=Path(tempfile.gettempdir()) / "episode.mp4",
            size_bytes=size_bytes,
            checksum_sha256="0" * 64,
            manifest={"task_id": "pick-and-place"},
        )

    def test_rejects_small_episode(self) -> None:
        result = BasicBuyerGate(minimum_size_bytes=1024).evaluate(
            self.make_input(size_bytes=100)
        )

        self.assertEqual(result.decision, GateDecision.REJECT)
        self.assertEqual(result.reason_code, "file_too_small")

    def test_routes_valid_episode_to_review(self) -> None:
        result = BasicBuyerGate(minimum_size_bytes=1024).evaluate(
            self.make_input(size_bytes=2048)
        )

        self.assertEqual(result.decision, GateDecision.REVIEW)
        self.assertEqual(result.plugin_version, "basic-size-gate-v1")
        self.assertEqual(result.scores["file_size"], 1.0)


if __name__ == "__main__":
    unittest.main()
