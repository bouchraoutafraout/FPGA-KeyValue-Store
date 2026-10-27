# MINI-BLOCKCHAIN FPGA - CONTRAT D'INTERFACES

Deadline : dimanche 01/11/2026

## Architecture cible
Mini-blockchain a un noeud, sans consensus distribue.
Un bloc par transaction acceptee.

## Format de bloc propose
- Index : 32 bits
- Previous hash : 256 bits
- Transaction : 64 bits
- Block hash : SHA-256 du contenu canonique du bloc

Contenu a hacher :
{index[31:0], previous_hash[255:0], transaction[63:0]}

Longueur : 352 bits.
Pour SHA-256, completer selon la norme SHA-256
avant le calcul, sans utiliser les hash Cuckoo.

## Sanae
- transaction_validator.v
- block_builder.v
- Controle des transactions
- Preparation de index + previous_hash + transaction
- Testbench pour chaque module

## Bouchra
- sha256_core.v
- chain_validator.v
- SHA-256 reel, verifie avec des vecteurs de test
- Verification du lien prev_hash entre blocs
- Testbench pour chaque module

## Khadija
- blockchain_storage.v
- Stockage des blocs et de leurs hash
- Gestion du bloc genesis
- Lecture par index
- Testbench pour ecriture et lecture

## Nada
- blockchain_top.v
- Connexion des modules
- CAN-FD aller-retour
- Verification des handshakes
- Testbench systeme
- Vivado, XDC, programmation et test FPGA

## Conditions de validation
- Une transaction acceptee cree un bloc
- Chaque bloc reference le hash precedent
- SHA-256 calcule le hash du bloc
- Un bloc modifie est detecte
- Le stockage reste coherent
- La simulation globale reussit
- La synthese et le timing FPGA sont verifies

IMPORTANT
Les ports exacts, la representation du bloc genesis,
les regles de validation et les signaux ready/busy/done
doivent etre convenus avant l'integration.
