# Diagnostic RTL : version fail-stop (NON VALIDEE)

Ne pas remplacer les sources originales. Extraire les fichiers .v et .ps1 dans Nada/Integration_Finale.
Dans PowerShell, lancer : & ".\Nada\Integration_Finale\run_guarded_tests.ps1"

ATTENTION: Les fichiers ne sont pas validés avec Icarus dans cet environnement.
Le test overflow force log_count=16 avec des entrees fictives : il ne demontre PAS la saturation naturelle par 16 ecritures. En cas de resultat FAIL, garder le log pour diagnostic, ne pas publier.

L'overflow devrait etre traite avant la construction du bloc lorsque le validateur signale l'erreur. La copie du controleur refuse explicitement le chemin de validation si txn_journal_overflow est haut.
Un timeout de stockage, dont l'issue est inconnue, declenche un verrouillage FAULT_LOCK apres la reponse. AUCUN rollback automatique dans ce chemin : il serait dangereux si la BRAM a deja ecrit. Une reprise materielle apres reset n'est pas couverte.
Le test de journal artificiellement plein peut generer des effets non representatifs. Les tests CREATE/TRANSFER/collision restent des cas limites, pas une preuve de correction generale.

Limites restantes : saturation reelle 16 ecritures, rollback sous multi-evictions, blocage d'autres requetes en FAULT_LOCK, echec de commit ou coupure d'alimentation, conservation des donnees apres reset.
