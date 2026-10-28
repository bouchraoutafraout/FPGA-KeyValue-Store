# Bouchra — SHA-256 et validation de blockchain

Sources: sha256_core.v, block_hash.v, chain_validator.v
Tests unitaires: tests/*_tb.v
Tests d integration: tests/blockchain_sha_reel_tb.v et tests/blockchain_sha_chain_tb.v

Les tests d integration utilisent aussi les modules de Nada et Khadija:
blockchain_top.v, blockchain_storage_adapter.v, blockchain_storage.v.
Ne PAS utiliser des copies des anciens fichiers de Nada/Khadija du ZIP original
sans verifier leur version contre la branche main actuelle.

Exemple (depuis ce dossier, avec Icarus Verilog):
iverilog -g2012 -s sha256_core_tb -o sha256_test.vvp tests/sha256_core_tb.v sha256_core.v
vvp sha256_test.vvp

Pour valider le SHA reel avec le stockage actuel, assembler un test temporaire
avec les sources a jour de Nada/Khadija (ne pas dupliquer leurs modules sur main).
