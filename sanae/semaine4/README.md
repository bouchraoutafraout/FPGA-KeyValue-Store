
##  Architecture générale

Le chemin fonctionnel principal est le suivant :

```text
Commande / Trame reçue
          |
          v
     cmd_decoder
          |
          v
 transaction_validator
          |
          +----------------------+
          |                      |
          v                      v
   cuckoo_top / KVS       block_builder
          |                      |
          v                      v
   Recherche / Mémoire     Calcul du hash
                                 |
                                 v
                         Stockage des blocs
                                 |
                                 v
                         Vérification de chaîne
```

Les détails exacts du chemin des signaux dépendent de la configuration utilisée dans chaque testbench.

## 3. Anciens modules réutilisés

Ces modules proviennent des étapes précédentes du projet. Ils constituent la base du Key-Value Store et du traitement des commandes.

| Fichier | Rôle |
|---|---|
| `cmd_decoder.v` | Décode les commandes reçues et extrait les informations d'une requête, notamment la commande, la clé et la valeur. |
| `cuckoo_insert.v` | Implémente la logique d'insertion basée sur le Cuckoo Hashing. |
| `hash_function1.v` | Première fonction de hachage utilisée par la structure Cuckoo. |
| `hash_function2.v` | Deuxième fonction de hachage utilisée par la structure Cuckoo. |
| `bram_table.v` | Fournit une table mémoire destinée au stockage des entrées du KVS. |
| `hashtables.v` | Organise les tables de hachage utilisées par le KVS. |
| `cuckoo_top.v` | Module de niveau supérieur qui coordonne les opérations du KVS basé sur le Cuckoo Hashing. |

**Important :** les fonctions de hachage `hash_function1.v` et `hash_function2.v` utilisées par le KVS ne sont pas le SHA-256 de la blockchain. Elles servent à déterminer l'emplacement des données dans les tables.

## 4. Modules ajoutés pour la blockchain

### 4.1 Validation des transactions

**Fichier : `transaction_validator.v`**

Ce module contrôle les transactions avant leur prise en compte par le système. Il participe à la gestion des commandes telles que :

- `CREATE` : créer une entrée dans le KVS.
- `SEARCH` : rechercher une clé.
- `TRANSFER` : modifier la valeur associée à une clé selon les règles implémentées.

Il permet notamment de rejeter les opérations invalides afin qu'elles ne produisent pas de nouveaux blocs.

### 4.2 Construction des blocs

**Fichier : `block_builder.v`**

Ce module construit les blocs à partir des transactions acceptées. Il coordonne la préparation des données du bloc, le calcul de son empreinte et son enregistrement.

**Fichier : `block_builder_real_sha.v`**

Cette variante du constructeur de blocs utilise le calcul SHA-256 réel intégré au projet, au lieu d'un simple modèle comportemental de hachage.

Elle permet de tester la construction de blocs avec une implémentation dédiée du SHA-256.

### 4.3 Calcul du hash

**Fichier : `block_hash.v`**

Ce module intervient dans le traitement du hachage des données des blocs. Il sert à intégrer le calcul ou l'interface de hachage dans le chemin de construction de la blockchain.

**Fichier : `sha256_core.v`**

Ce fichier contient le cœur de calcul SHA-256 utilisé par la version qui emploie le hachage réel.

Le SHA-256 produit une empreinte de 256 bits. Dans une blockchain, cette empreinte permet d'identifier le contenu d'un bloc et de détecter une modification des données hachées.

### 4.4 Stockage de la blockchain

**Fichier : `blockchain_storage.v`**

Ce module assure le stockage et la lecture des blocs. Il gère notamment l'état du stockage et le nombre de blocs enregistrés. La conception utilisée prévoit un bloc Genesis initial.

**Fichier : `chain_storage_if.v`**

Ce module fournit une interface entre la logique de vérification de la chaîne et le stockage des blocs, afin de permettre l'accès aux données nécessaires à leur contrôle.

### 4.5 Vérification de la chaîne

**Fichier : `chain_validator.v`**

Ce module vérifie l'intégrité de la blockchain. Il participe au contrôle des empreintes des blocs et de la relation entre un bloc et le hash du bloc précédent.

Si les données d'un bloc sont modifiées sans recalcul cohérent de son empreinte et des liens concernés, la vérification peut détecter l'incohérence.

## 5. Testbenches et validation

Les testbenches sont des fichiers de simulation. Ils servent à vérifier les modules et les scénarios fonctionnels.

| Fichier | Objectif |
|---|---|
| `tb_blockchain_e2e.v` | Test de bout en bout : commandes, validation des transactions, interactions avec le KVS, création des blocs, chaînage et détection d'altération. |
| `tb_chain_validator.v` | Vérification du comportement du validateur de chaîne. |
| `tb_block_builder_real_sha.v` | Vérification de la construction de blocs avec le SHA-256 réel. |
| `tb_blockchain_storage.v` | Vérification des opérations de stockage et de lecture des blocs. |
| `tb_transaction_validator.v` | Vérification de l'acceptation ou du rejet des transactions. |

Les noms et le contenu des testbenches doivent être comparés aux fichiers présents dans le dépôt avant de considérer cette liste comme exhaustive.

### Scénarios vérifiés dans le test de bout en bout

Le test `tb_blockchain_e2e.v` a notamment permis de vérifier :

- l'initialisation du bloc Genesis après le reset ;
- la création de clés et l'enregistrement des transactions acceptées ;
- le rejet de certaines transactions invalides ;
- l'absence de création de blocs pour les transactions rejetées ;
- la recherche des valeurs enregistrées ;
- la mise à jour d'une valeur par une transaction `TRANSFER` ;
- le chaînage des blocs par leurs empreintes ;
- la détection d'une altération du premier bloc par le contrôle SHA-256.

Le résultat de simulation obtenu est :

```text
MINI-BLOCKCHAIN DE BOUT EN BOUT : OK
```

Les avertissements liés aux directives `timescale` peuvent apparaître lorsque plusieurs fichiers utilisent des réglages temporels différents. Ils doivent être distingués des erreurs de compilation et des échecs de tests.

## 7. Compilation et exécution du test de bout en bout

Depuis le répertoire `sanae/semaine4`, la commande suivante compile les modules nécessaires au test de bout en bout :

```bash
iverilog -g2012 -Wall -s tb_blockchain_e2e \
-o sim_e2e \
../semaine3/cmd_decoder.v \
../semaine3/hash_function1.v \
../semaine3/hash_function2.v \
../semaine3/cuckoo_insert.v \
../semaine3/bram_table.v \
../semaine3/hashtables.v \
../semaine3/cuckoo_top.v \
transaction_validator.v \
block_builder.v \
block_builder_real_sha.v \
block_hash.v \
sha256_core.v \
blockchain_storage.v \
chain_storage_if.v \
chain_validator.v \
tb_blockchain_e2e.v
```

Lancer ensuite la simulation :

```bash
vvp sim_e2e
```

**Attention :** adapter les chemins `../semaine3/` à l'emplacement réel des anciens fichiers dans le dépôt. Si un module est absent du chemin indiqué, la compilation échouera.

## 8. Organisation des sources

Une organisation possible du dépôt est :

```text
FPGA-KeyValue-Store/
├── README.md
└── sanae/
    ├── semaine3/
    │   ├── cmd_decoder.v
    │   ├── cuckoo_insert.v
    │   ├── hash_function1.v
    │   ├── hash_function2.v
    │   ├── bram_table.v
    │   ├── hashtables.v
    │   └── cuckoo_top.v
    └── semaine4/
        ├── transaction_validator.v
        ├── block_builder.v
        ├── block_builder_real_sha.v
        ├── block_hash.v
        ├── sha256_core.v
        ├── blockchain_storage.v
        ├── chain_storage_if.v
        ├── chain_validator.v
        └── tb_blockchain_e2e.v
```
