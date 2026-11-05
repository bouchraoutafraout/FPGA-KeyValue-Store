# FPGA Blockchain Monitor

Dashboard Streamlit de supervision de la carte AC701 et de tests RTL locaux.

## Lancer

Dans PowerShell :

```powershell
py -m pip install -r requirements.txt
py -m streamlit run app.py
```

La connexion matérielle nécessite le pilote USB-UART et le port série de la carte (COM4 par défaut).
Fermez PuTTY et toute autre session Python détenant le port avant d’envoyer une commande.

## Protocole FPGA

- `PING` → `PONG`
- `Cxxxxxxxxvvvv` → `OK` ou erreur
- `Sxxxxxxxx` → `FOUND=hhhh` ou `MISS`
- `Txxxxxxxxvvvv` → `OK` ou erreur
- `Viiii` → `VALID`, `INVALID` ou `ERRVERIFY` (index de 0 à 15, exemple `V0000`)

Chaque commande ASCII se termine par CR (0x0D). Les réponses se terminent par CRLF. Débit : 115200, 8N1.

Le champ VERIFY vérifie un bloc existant : il ne crée aucun bloc.

## Simulation RTL

Les onglets de simulation nécessitent `iverilog` et `vvp` dans le PATH (par exemple MSYS2 UCRT64).
Ces simulations sont indépendantes des données réellement stockées dans le FPGA.

Les répertoires `rtl`, `tb` et `tests` contiennent les sources nécessaires aux simulations incluses.
Le nom technique de certains fichiers RTL est conservé afin de ne pas casser leurs dépendances.
