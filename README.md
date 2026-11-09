# Mini-Blockchain matérielle sur FPGA 🔗

**Conception, intégration et validation d'un registre chaîné sur FPGA Artix-7**, associant un moteur clé–valeur (*Cuckoo hashing*), un calcul SHA-256, un stockage en BRAM et une interface de commande UART. Un ensemble de modules CAN-FD a également été développé et évalué en simulation RTL.

> **Périmètre :** prototype académique de blockchain **locale**, sans réseau de nœuds ni mécanisme de consensus. Les essais sur carte réelle ont été réalisés via **UART** ; CAN-FD n'a pas été testé entre deux FPGA physiques.

## Fonctionnalités

- **CREATE** : création d'une association clé–valeur et inscription de la transaction acceptée dans la chaîne.
- **SEARCH** : recherche de la valeur associée à une clé (lecture de l'état courant).
- **TRANSFER** : mise à jour de la valeur et ajout d'une nouvelle transaction acceptée.
- **VERIFY** : vérification matérielle d'un bloc par recalcul du SHA-256 et contrôle du chaînage.
- **Supervision Streamlit** : envoi de commandes, réception des réponses UART et historique des opérations.
- **Développement CAN-FD** : émission, réception et contrôles de trames évalués à l'aide de testbenches RTL.

### Format des données

Un bloc applicatif occupe **608 bits** :

| Champ | Taille |
|---|---:|
| Index du bloc | 32 bits |
| Hash du bloc précédent | 256 bits |
| Transaction | 64 bits |
| SHA-256 du bloc | 256 bits |

Le calcul SHA-256 porte sur **352 bits (44 octets)** : index + hash précédent + transaction. Le hash stocké n'est pas inclus dans son propre calcul. Le stockage étudié comporte **16 emplacements**, dont un réservé au *Genesis* (jusqu'à 15 blocs applicatifs dans cette configuration).

## Matériel et outils

- Carte **Xilinx AC701**, FPGA **Artix-7 XC7A200T**.
- **Vivado 2026.1** pour la synthèse, l'implémentation, la programmation et les simulations XSim.
- Entrée d'horloge différentielle **200 MHz**, horloge système générée **50 MHz**.
- Connexions **JTAG** (programmation / ILA) et **USB-UART** (commandes).
- **Python**, **Streamlit**, **pyserial** pour le dashboard.
- **Icarus Verilog** (`iverilog`, `vvp`) pour certains tests RTL.

## Organisation du dépôt

Les principaux chemins sont :

```text
Bouchra/
  SHA256_ChainValidator_2026_10_28/  # SHA-256, vérificateur, testbenches
Khadija/
  semaine3/, semaine4/             # Tables, BRAM et stockage
sanae/
  semaine2/, semaine4/             # Cuckoo hashing, validation
Nada/
  CANFD/                            # Émission CAN-FD et tests
  Integration_CANFD/                # Réception CAN-FD et tests
  Integration_KV_CANFD/             # Adaptation CAN-FD / KVS
  Integration_Finale/               # Intégration RTL et tests de robustesse
  FPGA_Blockchain_Final/
    RTL/uart_blockchain_top.v       # Top de la démonstration matérielle
    Testbenches/                    # Tests UART et corruption simulée
    Dashboard/
      app.py
      fpga_uart.py
      requirements.txt
```

> Plusieurs variantes historiques de modules existent dans le dépôt. Pour la démonstration matérielle présentée ici, le top utilisé est **`uart_blockchain_top`**. Éviter de compiler simultanément des copies de modules portant le même nom.

## Lancer le dashboard

Dans PowerShell, depuis la racine du dépôt :

```powershell
cd .\Nada\FPGA_Blockchain_Final\Dashboard
py -m pip install -r requirements.txt
py -m streamlit run app.py
```

Pour les essais sur carte physique :

1. Programmer l'AC701 avec le bitstream correspondant au top UART.
2. Connecter la liaison USB-UART et repérer son port série (par exemple **COM4** lors de notre campagne).
3. Dans l'onglet **FPGA réel**, sélectionner le port et la commande à exécuter.
4. Utiliser **115200 bauds, 8N1**. Le protocole termine les commandes par **CR** et les réponses par **CRLF**.

### Protocole UART

| Opération | Exemple transmis | Réponse observée |
|---|---|---|
| CREATE (clé 1, valeur 100) | `C000000010064` | `OK` |
| SEARCH (clé 1) | `S00000001` | `FOUND=0064` |
| TRANSFER (clé 1, valeur 200) | `T0000000100C8` | `OK` |
| SEARCH après transfert | `S00000001` | `FOUND=00C8` |
| VERIFY bloc logique 0 | `V0000` | `VALID` |
| VERIFY bloc logique 1 | `V0001` | `VALID` |

Les chaînes ci-dessus sont montrées sans le caractère final `\r` pour faciliter la lecture.

## Résultats expérimentaux

### Sur FPGA réel — AC701 / UART

La campagne du **9 novembre 2026** a confirmé **six réponses positives** : `CREATE → SEARCH → TRANSFER → SEARCH → VERIFY 0 → VERIFY 1`. La seconde recherche a retourné la nouvelle valeur (`00C8`, soit 200 en décimal) et les deux blocs logiques testés ont été acceptés (`VALID`). Une capture ILA a également permis d'observer un hash interne sur 256 bits.

**Utilisation du top UART final (synthèse Vivado)** :

| Ressource | Utilisation |
|---|---:|
| LUT | 4 228 |
| Flip-flops | 5 605 |
| RAMB36 | 10 |
| RAMB18 | 1 |
| DSP | 0 |

**Timing après routage** : **WNS = +4,298 ns**, **TNS = 0 ns** pour l'horloge système de **50 MHz**. Ces chiffres ne constituent pas, à eux seuls, une validation exhaustive de toutes les contraintes d'interface.

### Intégrité — simulation RTL

Un test sous **Vivado XSim** a vérifié le scénario : **bloc intact → `VALID`**, puis inversion contrôlée d'un bit du hash en mémoire simulée → **`INVALID`**. Ce test prouve la détection de cette corruption **en simulation** ; aucune injection équivalente n'a été effectuée sur la BRAM physique de l'AC701.

### CAN-FD — simulation RTL uniquement

| Banc de test | Observation |
|---|---|
| `canfd_tx_tb.v` | **PASS** — trame émise, CRC-17 `1BBF9`, acquittement ACK reçu |
| `canfd_rx_tb_crc_error_real.v` | **PASS** — erreur CRC-17 détectée, `crc_ok=0`, `frame_valid=0` |
| `canfd_rx_tb.v` | Banc de réception disponible ; verdict de réussite à confirmer à partir de sa sortie complète |
| `canfd_blockchain_full_tb.v` | **FAIL** — cinq timeouts lors du test d'intégration complet |

La communication **CAN-FD entre deux cartes FPGA** n'a **pas** été démontrée faute de liaison matérielle adaptée. Le test d'intégration complet n'a pas encore été validé. Les réussites des tests TX/CRC ne doivent donc pas être interprétées comme une validation de l'ensemble de la chaîne CAN-FD ↔ blockchain.

### Moteur Cuckoo — limites observées

Dans une campagne de **100 clés pseudo-aléatoires**, le journal indique **30 évictions, un échec et une clé perdue**. Un scénario forcé sur trois clés entrant en collision expose également une limite de cette variante. Ces observations sont conservées dans l'évaluation plutôt que d'affirmer une réussite exhaustive.

## Reproduire une simulation

**Test d'émission CAN-FD** (depuis `Nada/CANFD`) :

```powershell
iverilog -g2012 -s canfd_tx_tb -o canfd_tx_test.vvp `
  canfd_tx_tb.v canfd_tx.v canfd_bit_timer.v `
  canfd_crc.v canfd_crcfield.v canfd_stuffer.v
vvp canfd_tx_test.vvp
```

**Test de corruption UART / blockchain sous Vivado** : ajouter les fichiers RTL nécessaires et `uart_blockchain_corruption_tb.v` au projet de simulation, puis dans la console Tcl :

```tcl
set_property top uart_blockchain_corruption_tb [get_filesets sim_1]
launch_simulation -mode behavioral
run 50 ms
```

Le test de corruption accède à des signaux internes du design : sa hiérarchie doit correspondre à la version RTL simulée.

## Limites et perspectives

- Registre cryptographiquement chaîné **à un seul nœud**, sans consensus distribué ni signature des transactions.
- Mémoire BRAM expérimentale de capacité limitée et **non persistante après coupure**.
- Absence d'authentification et de chiffrement des commandes UART dans cette démonstration.
- Cas extrêmes d'évictions Cuckoo, saturation du journal et reprise après panne non couverts de manière exhaustive.
- Validation CAN-FD inter-FPGA et résolution des timeouts d'intégration restant à réaliser.
- Vérification indépendante des empreintes SHA-256 sur les octets canoniques d'entrée à compléter.

## Équipe

Projet réalisé à l'**Institut National des Postes et Télécommunications (INPT)**, filière **Systèmes embarqués et services numériques**, année universitaire **2026–2027**.

- Sanae **BAAZIZ**
- Khadija **MOSSAMIH**
- Nada **OUALADI**
- Bouchra **OUTAFRAOUT**

**Encadrement :** Pr. Meryeme **AYACHE**.

## Licence

Aucune licence open source n'est déclarée dans ce README. Ajouter un fichier `LICENSE` uniquement après accord des membres de l'équipe sur les conditions de diffusion du projet.
