
POLY = 0x1685B
INIT = 0x10000
MASK = 0x1FFFF

def bits_msb(value, width):
    return [(value >> i) & 1 for i in range(width - 1, -1, -1)]

def build_bits(can_id, data, dlc):
    bits = [0]                       # SOF
    bits += bits_msb(can_id, 11)     # Identifiant
    bits += [1, 0, 1, 0, 0, 0]      # Controle actuel
    bits += bits_msb(dlc, 4)        # DLC
    bits += bits_msb(data, 64)[:8 * dlc]
    return bits

def apply_stuffing(bits):
    result = []
    previous = None
    count = 0

    for bit in bits:
        if count == 5:
            opposite = 1 - previous
            result.append(opposite)
            previous = opposite
            count = 1

        result.append(bit)

        if bit == previous:
            count += 1
        else:
            previous = bit
            count = 1

    return result

def calculate_crc(bits):
    crc = INIT

    for bit in bits:
        feedback = ((crc >> 16) & 1) ^ bit
        crc = (crc << 1) & MASK

        if feedback:
            crc ^= POLY

    return crc

tests = [
    (0x100, 0x0000000000000000, 0, 0x1935B),
    (0x123, 0xA5C3000000000000, 2, 0x14E0A),
    (0x456, 0x123456789ABCDEF0, 8, 0x0231A),
]

errors = 0

for can_id, data, dlc, expected in tests:
    useful_bits = build_bits(can_id, data, dlc)
    stuffed_bits = apply_stuffing(useful_bits)
    crc = calculate_crc(stuffed_bits)

    print(f"\nID=0x{can_id:03X} DLC={dlc}")
    print(f"Bits utiles : {len(useful_bits)}")
    print(f"Bits stuffing : {len(stuffed_bits) - len(useful_bits)}")
    print(f"CRC Python : 0x{crc:05X}")
    print(f"CRC Verilog: 0x{expected:05X}")

    if crc == expected:
        print("PASS")
    else:
        errors += 1
        print("FAIL")

print("\n==========================")
print(f"Erreurs : {errors}")
print("TEST CRC REUSSI" if errors == 0 else "TEST CRC ECHEC")
