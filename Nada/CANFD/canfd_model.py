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

if __name__ == "__main__":
    d = [(c >> i) & 1 for c in b"123456789" for i in range(7, -1, -1)]
    assert crc(d, 17, 0x1685B, 0) == 0x04F03 and crc(d, 21, 0x102899, 0) == 0x0ED841
    print("CRC-17 et CRC-21 : valeurs de controle du catalogue OK")
