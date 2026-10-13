# Modele de reference (Python) pour l'emetteur CAN FD : sert a calculer les valeurs attendues
# et a verifier le Verilog. A comparer ensuite avec une trame CAN FD reelle (analyseur, autre noeud).

def stuff(bits):
    """Bourrage dynamique : apres 5 bits identiques, insere le bit oppose.
    Retourne (bits_emis, nombre_de_bits_de_bourrage)."""
    out, last, run, cnt = [], None, 0, 0
    for b in bits:
        if run == 5:                      # bourrage avant d'emettre b
            s = 1 - last
            out.append(s); cnt += 1
            last, run = s, 1
        out.append(b)
        run = run + 1 if (run != 0 and b == last) else 1
        last = b
    if run == 5:                          # le bourrage est aussi insere apres le dernier bit
        s = 1 - last
        out.append(s); cnt += 1
    return out, cnt

def crc(bits, width, poly, init):
    r, top, mask = init, 1 << (width - 1), (1 << width) - 1
    for b in bits:
        fb = ((r & top) != 0) ^ b
        r = (r << 1) & mask
        if fb:
            r ^= poly
    return r

def crc17(bits, init=0x10000): return crc(bits, 17, 0x1685B, init)
def crc21(bits, init=0x100000): return crc(bits, 21, 0x102899, init)

# ---- champ CRC : compteur de bourrage (Gray + parite paire) et bits de bourrage fixes ----
GRAY = {0: "000", 1: "001", 2: "011", 3: "010", 4: "110", 5: "111", 6: "101", 7: "100"}

def crc_field(prev_bit, stuff_count, crc_value, is21):
    """Retourne (bits sous forme de chaine, nombre de bits de bourrage fixes).
    prev_bit : dernier bit emis avant le champ ; stuff_count : bits de bourrage dynamiques."""
    g = GRAY[stuff_count % 8]
    parity = str(g.count("1") % 2)                       # parite paire
    width = 21 if is21 else 17
    payload = g + parity + format(crc_value, "0%db" % width)
    out, fsb, p = [], 0, int(prev_bit)
    out.append(1 - p); fsb += 1; p = 1 - p               # bit fixe initial
    for i, c in enumerate(payload):
        b = int(c); out.append(b); p = b
        if (i + 1) % 4 == 0 and (i + 1) < len(payload):  # bit fixe apres chaque 4 bits
            out.append(1 - p); fsb += 1; p = 1 - p
    return "".join(map(str, out)), fsb


if __name__ == "__main__":
    d = [(c >> i) & 1 for c in b"123456789" for i in range(7, -1, -1)]
    assert crc(d, 17, 0x1685B, 0) == 0x04F03 and crc(d, 21, 0x102899, 0) == 0x0ED841
    print("CRC-17 et CRC-21 : valeurs de controle du catalogue OK")
    assert crc_field(0, 0, 0x00000, False) == ("100001000010000100001000010", 6)
    assert crc_field(1, 3, 0x1FFFF, False) == ("001010111101111011110111101", 6)
    assert crc_field(0, 7, 0x155555, True) == ("11001010101101011010110101101011", 7)
    print("Champ CRC (compteur + bits fixes) : 3 sequences de reference OK")
