Enregistrez ce texte dans un fichier nommé README.md, placé dans le dossier contenant SniperClip.ps1. Le kit de build le copiera automatiquement dans dist\\ à chaque compilation.



SniperClip



SniperClip est un gestionnaire de presse-papiers léger pour Windows. Il capture le presse-papiers dans une grille de cellules cliquables : chaque cellule mémorise un contenu (texte ou autre), peut être colorée, renommée et re-collée d'un simple clic, avec un aperçu au survol.



Auteur : Vincent VELIO



Version : 1.0



Plateforme : Windows (PowerShell 5.1 + Windows Forms, aucune installation)



Licence : MIT (Open source) — voir le fichier LICENSE



Fonctionnalités



Grille de cellules de capture du presse-papiers, collage en un clic.



Couleur de fond et nom personnalisables par cellule.



Aperçu du contenu au survol, polices adaptées à la taille des cellules.



Historique persistant dans une base SQLite (%APPDATA%\\SniperClip).



Icône systray avec menu complet (About, démarrage avec Windows, langue).



Raccourci global d'affichage/masquage (Ctrl+Alt+V).



Fenêtre agrandissable, plein écran ou moitié d'écran ; la taille et la position sont mémorisées.



Jump List de la barre des tâches (cellules les plus récentes).



Export / import de la configuration.



Installation



Téléchargez SniperClip.exe.



Placez-le où vous voulez (par ex. %LOCALAPPDATA%\\SniperClip\\) et lancez-le : aucune installation n'est requise.



Au premier lancement, Windows peut afficher un avertissement SmartScreen : cliquez sur « Informations complémentaires » puis « Exécuter quand même » (l'exe n'est pas encore connu de Microsoft).



Les données (base, sauvegarde, journal) sont stockées dans %APPDATA%\\SniperClip.



Compilation depuis les sources



L'exécutable est généré à partir de SniperClip.ps1 avec le kit de build :



powershell -ExecutionPolicy Bypass -File .\\build.ps1



Le script crée une copie adaptée dans build\\, la compile avec ps2exe dans dist\\SniperClip.exe et y copie LICENSE et README.md. Options : -Sign -SelfSigned pour signer l'exe avec un certificat auto-signé local, ou -Thumbprint <empreinte> pour un certificat OV/EV.



Licence



Code distribué sous licence MIT — voir le fichier LICENSE. Vous êtes libre de l'utiliser, de le modifier et de le redistribuer, à condition de conserver la mention de copyright.

