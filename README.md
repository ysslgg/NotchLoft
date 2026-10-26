<div align="center">

<img src="Resources/AppIcon-1024.png" width="128" alt="Icône de NotchTune">

# NotchTune

**La musique en cours, dans l'encoche de ton MacBook.**

Pochette, titre, progression et contrôles, au bout de ta souris : l'encoche devient un lecteur discret.

[![Télécharger NotchTune](https://img.shields.io/badge/%E2%AC%87%EF%B8%8E%20T%C3%A9l%C3%A9charger-NotchTune.dmg-8A2BE2?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ysslgg/NotchTune/releases/latest/download/NotchTune.dmg)

![Dernière version](https://img.shields.io/github/v/release/ysslgg/NotchTune?color=8A2BE2&label=version)
![Téléchargements](https://img.shields.io/github/downloads/ysslgg/NotchTune/total?color=ec4899&label=t%C3%A9l%C3%A9chargements)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-444?logo=apple&logoColor=white)
![Apple Silicon et Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-444)

<br>

<img src="docs/hover.png" width="520" alt="NotchTune au survol : pochette, titre, progression et boutons">

<sub>Au survol</sub>

<br>

<img src="docs/compact.png" width="520" alt="NotchTune au repos : pochette à gauche, visualiseur à droite">

<sub>Au repos</sub>

</div>

## Fonctionnalités

- **Tout ce qui joue** : lit le « Now Playing » du système, donc Apple Music, Spotify, ton navigateur…
- **Au repos**, l'encoche s'élargit juste un peu : pochette à gauche (entourée d'une bague de progression), visualiseur animé à droite, symbole pause quand la lecture est en pause. Rien ne s'affiche quand rien ne joue.
- **Au survol**, elle s'agrandit : pochette, titre et artiste (qui défilent s'ils sont longs), barre de progression à cliquer ou glisser pour avancer dans le morceau, temps écoulé et restant, précédent / lecture-pause / suivant.
- **Aux couleurs de la pochette** : la couleur d'accent est extraite de l'image (barres, progression, halo, dégradé de fond), ou choisie parmi des teintes fixes.
- **Un clic sur l'icône de l'app** (Spotify, Musique…) l'ouvre directement.
- **Personnalisable** depuis l'icône de la barre des menus : visualiseur, bague de progression, fond flou, retour haptique, couleur d'accent, largeur au repos, masquage après une pause, lancement au démarrage.
- **Discret** : aucune icône dans le Dock, seulement une icône dans la barre des menus pour régler l'app ou la quitter.
- **Pour tous les Mac** : sur un Mac sans encoche, une encoche simulée prend le relais.

## Installation

1. Télécharge **NotchTune.dmg** avec le bouton ci-dessus.
2. Ouvre le DMG et glisse **NotchTune** dans **Applications**.
3. Au premier lancement, macOS affiche un avertissement car l'app n'est pas notarisée. Ouvre **Réglages Système → Confidentialité et sécurité**, descends jusqu'à NotchTune et clique sur **Ouvrir quand même**.

## Limites

- Le visualiseur est purement décoratif : il ne capte pas le son.
- L'app n'est pas notarisée par Apple, d'où l'avertissement au premier lancement.
- Les informations affichées dépendent de ce que l'application de lecture transmet au système : certains lecteurs n'envoient ni pochette ni durée.
- Usage personnel uniquement, voir la [licence](LICENSE).
