
import csv

# Trame actuellement testee
CAN_ID = 0x123
DLC = 2
DATA = bytes.fromhex("A51F")

CRC_POLY = 0x1685B
CRC_INIT = 0x10000
CRC_MASK = 0x1FFFF


def bits_msb(value, width):
    return [
        (value >> i) & 1
        for i in range(width - 1, -1, -1)
    ]


def build_payload():
    bits = [0]                  # SOF
    bits += bits_msb(CAN_ID, 11)
    bits += [1, 0, 1, 0, 0, 0]  # Controle TX actuel
    bits += bits_msb(DLC, 4)

    for byte in DATA:
        bits += bits_msb(byte, 8)

    return bits


def dynamic_stuff(bits):
    output = []
    previous = None
    run = 0
    count = 0

    for bit in bits:

        if run == 5:
            inserted = 1 - previous
            output.append(inserted)
            previous = inserted
            run = 1
            count += 1

        output.append(bit)

        if bit == previous:
            run += 1
        else:
            previous = bit
            run = 1

    return output, count


def build_sbc(count):
    value = count % 8
    gray = value ^ (value >> 1)

    result = bits_msb(gray, 3)
    parity = sum(result) % 2

    return result + [parity]


def crc17(bits):
    crc = CRC_INIT

    for bit in bits:
        feedback = ((crc >> 16) & 1) ^ bit
        crc = (crc << 1) & CRC_MASK

        if feedback:
            crc ^= CRC_POLY

    return crc


def fixed_stuff_field(previous, field):
    output = []
    last = previous

    # Premier bit de stuffing fixe
    fsb = 1 - last
    output.append(fsb)
    last = fsb

    for i, bit in enumerate(field):

        output.append(bit)
        last = bit

        # Stuffing fixe apres chaque groupe de 4
        if (i + 1) % 4 == 0:
            fsb = 1 - last
            output.append(fsb)
            last = fsb

    return output


# Construire la trame de reference
payload = build_payload()
stuffed, stuff_count = dynamic_stuff(payload)

sbc = build_sbc(stuff_count)
crc = crc17(stuffed + sbc)
crc_bits = bits_msb(crc, 17)

crc_field = fixed_stuff_field(
    stuffed[-1],
    sbc + crc_bits
)

# Sequence finale de l'implementation actuelle
tail = [1] * 10

expected = stuffed + crc_field + tail

# Lire la capture CAN_TX
with open("canfd_wire_bits.csv", newline="") as f:
    rows = list(csv.DictReader(f))

actual = [int(row["can_tx"]) for row in rows]

print("===================================")
print("VERIFICATION CAN FD TX")
print("===================================")

print(f"ID              : 0x{CAN_ID:03X}")
print(f"DATA            : {DATA.hex().upper()}")
print(f"Bits utiles     : {len(payload)}")
print(f"Stuff dynamique : {stuff_count}")
print(f"SBC             : {''.join(map(str, sbc))}")
print(f"CRC-17          : 0x{crc:05X}")
print(f"Champ CRC       : {len(crc_field)} bits")
print(f"Bits attendus   : {len(expected)}")
print(f"Bits captures   : {len(actual)}")

errors = 0

if len(actual) != len(expected):
    print("FAIL : longueur differente")
    errors += 1

for i, (a, e) in enumerate(zip(actual, expected)):
    if a != e:
        print(f"FAIL bit {i}: capture={a} attendu={e}")
        errors += 1

print("===================================")

if errors == 0:
    print("PASS : comparaison bit a bit")
    print("=== TEST TRAME REUSSI ===")
else:
    print(f"=== {errors} ERREUR(S) ===")
