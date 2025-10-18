
# Minimal PCG32 PRNG for deterministic sims (no external deps)
# Source: public domain style reference implementation, simplified
from dataclasses import dataclass

@dataclass
class PCG32:
    state: int
    inc: int = 1442695040888963407  # default stream

    def next_u32(self) -> int:
        oldstate = self.state & ((1<<64)-1)
        self.state = (oldstate * 6364136223846793005 + (self.inc | 1)) & ((1<<64)-1)
        xorshifted = (((oldstate >> 18) ^ oldstate) >> 27) & ((1<<32)-1)
        rot = (oldstate >> 59) & 31
        return (xorshifted >> rot) | ((xorshifted << ((-rot) & 31)) & 0xFFFFFFFF)

    def random(self) -> float:
        return self.next_u32() / 2**32

    def randint(self, a:int, b:int) -> int:
        # inclusive a..b
        span = b - a + 1
        return a + int(self.random() * span)
