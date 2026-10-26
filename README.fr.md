<div align="center">

**[English](README.md) · Français**

<img src="Resources/AppIcon-1024.png" width="128" alt="Icône de NotchLoft">

# NotchLoft

**La boîte à outils cachée dans l'encoche de ton MacBook.**

Musique en cours, presse-papier, étendoir à captures, dépôt de fichiers, batterie et système : survole l'encoche, tout est là.

[![Télécharger NotchLoft](https://img.shields.io/badge/%E2%AC%87%EF%B8%8E%20T%C3%A9l%C3%A9charger-NotchLoft.dmg-8A2BE2?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ysslgg/NotchLoft/releases/latest/download/NotchLoft.dmg)

![Dernière version](https://img.shields.io/github/v/release/ysslgg/NotchLoft?color=8A2BE2&label=version)
![Téléchargements](https://img.shields.io/github/downloads/ysslgg/NotchLoft/total?color=ec4899&label=t%C3%A9l%C3%A9chargements)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-444?logo=apple&logoColor=white)
![Apple Silicon et Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-444)

<br>

<img src="docs/fr/hover.png" width="460" alt="La musique en cours, au survol de l'encoche">

<sub>Musique</sub>

<img src="docs/fr/shelf.png" width="460" alt="L'étendoir : les dernières captures d'écran accrochées à une corde à linge">

<sub>Étendoir à captures d'écran</sub>

<img src="docs/fr/clipboard.png" width="400" alt="L'historique du presse-papier">

<sub>Presse-papier</sub>

<img src="docs/fr/files.png" width="460" alt="Le dépôt de fichiers : fichiers accrochés à la corde à linge">

<sub>Dépôt de fichiers</sub>

<img src="docs/fr/system.png" width="420" alt="Batterie et système : niveau de batterie, processeur, mémoire et disque">

<sub>Batterie et système</sub>

<br>

<img src="docs/fr/compact.png" width="460" alt="L'encoche au repos : pochette à gauche, visualiseur à droite">

<sub>Au repos</sub>

</div>

## Fonctionnalités

### 🎵 Musique
- Lit le « Now Playing » du système : Apple Music, Spotify, ton navigateur…
- **Au repos**, l'encoche s'élargit juste un peu : pochette à gauche (avec une bague de progression), visualiseur animé à droite (les barres suivent le son, graves à gauche et aigus à droite), symbole pause en pause. Rien ne s'affiche quand rien ne joue.
- **Au survol** : pochette, titre et artiste (qui défilent s'ils sont longs), barre de progression à cliquer ou glisser, temps écoulé et restant, précédent / lecture-pause / suivant. Un clic sur l'icône de l'app ouvre Spotify, Musique…
- Couleurs d'accent tirées de la pochette, ou teintes fixes au choix.

### 📋 Presse-papier
- Historique du texte copié (30 éléments), un clic remet l'élément dans le presse-papier.
- Épingle les éléments importants : ils restent, même après un redémarrage.
- Les copies de mots de passe (1Password et autres gestionnaires) ne sont jamais enregistrées.

### 🧷 Étendoir à captures d'écran
- Tes dernières captures (jusqu'à 30) s'accrochent à une corde à linge, avec leurs pinces. Fais défiler à gauche ou à droite pour voir les autres.
- **Tout y passe** : captures d'écran, **enregistrements d'écran** (avec leur durée), et captures copiées dans le presse-papiers (⌃⇧⌘3 / ⌃⇧⌘4).
- **Animation** : à chaque nouvelle capture, la miniature s'envole vers l'encoche, qui s'ouvre un instant pour l'accrocher.
- Clic pour ouvrir, **glisse-dépose** vers n'importe quelle app, **croix** au survol pour retirer une capture de l'étendoir (le fichier reste intact), clic droit pour copier, afficher dans le Finder ou mettre à la corbeille.

### 📥 Dépôt de fichiers
- Glisse un fichier ou un dossier sur l'encoche : elle s'ouvre toute seule et il s'accroche à la corde à linge.
- Reprends-le plus tard par glisser-déposer vers n'importe quelle app. Rien n'est copié ni déplacé, ce sont des raccourcis vers tes fichiers.
- Clic pour ouvrir, croix pour retirer, clic droit pour l'afficher dans le Finder ou copier son chemin.

### 🔋 Batterie et système
- Niveau, état de charge, temps restant, santé et cycles de la batterie, plus processeur, mémoire et disque.
- **Tu choisis ce qui s'affiche en grand** : clique sur une jauge pour la mettre en avant (ou utilise le menu ♪). Le processeur y ajoute sa courbe en direct.

### Et aussi
- **Onglets** dans les ailes de l'encoche pour passer d'un outil à l'autre.
- **Anglais ou français** : l'interface est en anglais par défaut ; passe en français dans le menu ♪ → Langue.
- **Personnalisable** depuis l'icône de la barre des menus : page à l'ouverture (par défaut ou la dernière utilisée), activer ou non chaque outil, visualiseur, bague de progression, fond flou, retour haptique, couleur d'accent, largeur au repos, masquage après une pause, lancement au démarrage, vérification des mises à jour.
- **Discret** : aucune icône dans le Dock, et l'encoche se masque au repos dans les apps en plein écran (elle s'ouvre toujours quand tu survoles l'encoche). Réglable dans le menu ♪.
- **Pour tous les Mac** : sur un Mac sans encoche, une encoche simulée prend le relais.

## Installation

1. Télécharge **NotchLoft.dmg** avec le bouton ci-dessus.
2. Ouvre le DMG et glisse **NotchLoft** dans **Applications**.
3. Au premier lancement, macOS affiche un avertissement car l'app n'est pas notarisée. Ouvre **Réglages Système → Confidentialité et sécurité**, descends jusqu'à NotchLoft et clique sur **Ouvrir quand même**.
4. Pour l'étendoir, autorise l'accès au dossier des captures (Bureau par défaut) quand macOS te le demande.

## Limites

- Le presse-papier ne garde que le texte, pas les images ni les fichiers.
- L'étendoir ne voit pas les captures envoyées directement vers une app (Mail, Messages…) : elles n'existent ni en fichier ni dans le presse-papiers.
- Le visualiseur suit le son du Mac quand tu l'autorises (macOS 14.2 ou plus) ; sans autorisation, il reste une animation décorative. Il ne voit pas le son protégé par DRM.
- L'app n'est pas notarisée par Apple, d'où l'avertissement au premier lancement.
- Les informations de lecture dépendent de ce que l'app transmet au système : certains lecteurs n'envoient ni pochette ni durée.
- Usage personnel uniquement, voir la [licence](LICENSE).
