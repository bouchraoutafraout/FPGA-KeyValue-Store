
from vcdvcd import VCDVCD

vcd = VCDVCD("canfd_timing.vcd", store_tvs=True)

signals = [
    "tick",
    "crc_valid",
    "crc_done",
    "tail_valid",
    "can_tx"
]

for signal in signals:
    matches = [
        name for name in vcd.signals
        if name.split(".")[-1] == signal
    ]

    if not matches:
        print(f"{signal}: introuvable")
        continue

    print(f"\n=== {signal} ===")

    for t, value in vcd[matches[0]].tv:
        # Examiner uniquement la zone 63-68 microsecondes
        if 63000000 <= t <= 68000000:
            print(f"{t / 1_000_000:.3f} us : {value}")
