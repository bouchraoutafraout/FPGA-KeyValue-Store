
from vcdvcd import VCDVCD
import matplotlib.pyplot as plt

vcd = VCDVCD("canfd_tx.vcd", store_tvs=True)

# Afficher les signaux disponibles
print("Signaux disponibles :")
for name in vcd.signals:
    print(name)

wanted = ["can_tx", "busy", "done", "tick", "crc_valid", "tail_valid"]

fig, axes = plt.subplots(len(wanted), 1, figsize=(14, 9), sharex=True)

for ax, target in zip(axes, wanted):
    matches = [
        name for name in vcd.signals
        if name.split(".")[-1] == target
    ]

    if not matches:
        ax.text(0.5, 0.5, "Signal introuvable",
                transform=ax.transAxes, ha="center")
        ax.set_ylabel(target)
        continue

    signal = vcd[matches[0]]
    values = signal.tv

    times = [t / 1_000_000 for t, _ in values]
    bits = [
        int(v) if v in ("0", "1") else 0
        for _, v in values
    ]

    ax.step(times, bits, where="post")
    ax.set_ylabel(target)
    ax.set_yticks([0, 1])
    ax.grid(True)

axes[-1].set_xlabel("Temps (microsecondes)")
plt.suptitle("Chronogrammes CAN FD")
plt.tight_layout()
plt.show()
