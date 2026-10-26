
import csv

with open("canfd_wire_bits.csv", newline="") as f:
    rows = list(csv.DictReader(f))

bits = [int(row["can_tx"]) for row in rows]

errors = 0

def check(name, condition):
    global errors
    if condition:
        print("PASS :", name)
    else:
        print("FAIL :", name)
        errors += 1

check("Longueur = 77 bits", len(bits) == 77)

if len(bits) >= 41:
    check("Cinq derniers bits utiles = 11111",
          bits[34:39] == [1, 1, 1, 1, 1])

    check("Stuffing dynamique final = 0",
          bits[39] == 0)

    check("Premier bit fixe CRC = 1",
          bits[40] == 1)
else:
    check("Capture suffisamment longue", False)

print("-------------------------------")
print("Erreurs :", errors)

if errors == 0:
    print("=== TEST FRONTIERE CRC REUSSI ===")
else:
    print("=== TEST FRONTIERE CRC ECHEC ===")
