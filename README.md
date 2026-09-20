# scanpeople

Ce projet permet d'utiliser la caméra d'un iPhone comme une webcam sur cette
machine Linux. Une fois tout démarré, l'iPhone apparaît comme une caméra
« normale » : OBS, Zoom, Chrome ou n'importe quel logiciel vidéo peuvent
s'en servir comme si c'était une webcam USB branchée sur l'ordinateur.

## Prérequis

- L'iPhone et l'ordinateur doivent être sur le **même réseau Wi-Fi**.
- L'app de streaming (OctoStream) doit être installée sur l'iPhone.
- Les dépendances système doivent être installées : `./install-deps.sh`.
- L'adresse IP de l'iPhone doit être renseignée dans le fichier `.env` :

## Récapitulatif

| Étape | Commande | Effet sur le système |
|-------|----------|----------------------|
| 1 | `make stream` | Crée la fausse webcam `/dev/video42` et y déverse la vidéo de l'iPhone |
| 2 | `flatpak run --device=all org.videolan.VLC v4l2:///dev/video42` | Affiche le résultat pour vérifier |
| 3 | `make detect` | Affiche le flux avec un carré autour de chaque visage |

Une fois l'étape 1 lancée, n'importe quelle application vidéo peut
sélectionner « iPhone Virtual Camera » dans sa liste de caméras.



## Étape 1 — Lancer le flux

Lance d'abord le streaming dans l'app OctoStream sur l'iPhone, puis, sur
l'ordinateur, **une seule commande suffit** :

```bash
make stream
```

Elle enchaîne deux choses : la création de la caméra virtuelle, puis le
branchement de l'iPhone dessus. Les deux sections ci-dessous détaillent l'une
et l'autre.

### Ce qui se passe réellement — 1. la caméra virtuelle

Sous Linux, chaque caméra est représentée par un fichier spécial dans
`/dev/` : une vraie webcam USB apparaît par exemple comme `/dev/video0`.
Les logiciels vidéo ne savent lire que ce genre de fichier.

Le problème : l'iPhone n'est pas branché en USB, il envoie sa vidéo par le
réseau. Il n'existe donc aucun `/dev/videoX` qui lui corresponde.

`make stream` règle ça en appelant d'abord le script `start.sh`, qui charge
dans le noyau Linux un module appelé **v4l2loopback**. Ce module crée une
**fausse caméra** — une caméra qui n'existe pas physiquement, mais que le
système traite exactement comme une vraie. Concrètement, à ce stade :

- un nouveau fichier `/dev/video42` apparaît sur la machine ;
- il porte le nom « iPhone Virtual Camera » dans les applications ;
- pour l'instant il est **vide** : la caméra existe, mais personne ne lui
  envoie encore d'image.

Le numéro 42 est choisi volontairement haut pour ne pas entrer en conflit
avec une vraie webcam déjà présente.

Quelques précisions utiles :

- La commande demande le **mot de passe sudo** : charger un module dans le
  noyau est une opération système, elle nécessite les droits administrateur.
- **Rien n'est écrit sur le disque.** La caméra virtuelle vit uniquement en
  mémoire, elle disparaît au redémarrage de l'ordinateur.
- Si la caméra existe déjà, cette partie ne fait rien de plus : elle le
  signale et passe à la suite. C'est pourquoi `make stream` peut être relancé
  autant de fois que nécessaire, y compris plusieurs fois dans la même
  session, sans jamais rien casser.

Le script reste utilisable seul, pour inspecter ou nettoyer :

```bash
./start.sh --status   # la caméra virtuelle est-elle active ?
./start.sh --stop     # supprime la caméra virtuelle
```

`--stop` échoue volontairement si une application est en train d'utiliser la
caméra, pour éviter de couper un flux en cours par accident.

### Ce qui se passe réellement — 2. le branchement de l'iPhone

L'app sur l'iPhone diffuse la vidéo sur le réseau local, à une adresse du
type `rtsp://<IP_de_l_iPhone>:554/stream`. C'est un flux réseau : sans rien
de plus, l'ordinateur peut le recevoir, mais aucune application vidéo ne
saura le considérer comme une caméra.

Une fois la caméra virtuelle en place, `make stream` lance **GStreamer**, un
outil qui joue le rôle de tuyau entre les deux mondes. Il :

1. se connecte au flux vidéo de l'iPhone sur le réseau ;
2. décompresse les images (elles arrivent compressées en H.264) ;
3. les écrit en continu dans `/dev/video42`, la caméra virtuelle créée juste
   avant.

À partir de ce moment, la caméra virtuelle n'est plus vide : elle diffuse en
direct ce que filme l'iPhone. Tout logiciel qui ouvre « iPhone Virtual
Camera » voit l'image du téléphone.

Points à retenir :

- Cette commande **reste active** dans le terminal tant que le flux tourne.
  C'est normal : le tuyau doit rester ouvert. Il faut donc laisser ce
  terminal ouvert et en ouvrir un autre pour la suite.
- `Ctrl+C` coupe le flux. La caméra virtuelle, elle, continue d'exister
  (simplement vide à nouveau) : il suffit de relancer `make stream`.
- Si le port utilisé par l'app n'est pas le port 554 par défaut :

  ```bash
  PORT=8554 make stream
  ```

## Étape 2 — Vérifier que l'image arrive bien

Dans un **second terminal** (le premier étant occupé par `make stream`) :

```bash
vlc v4l2:///dev/video42
```

Cette commande demande à VLC d'ouvrir non pas un fichier vidéo, mais la
caméra virtuelle : c'est le sens du préfixe `v4l2://` (Video4Linux2, le
système de gestion des caméras sous Linux). Si tout fonctionne, la fenêtre
VLC affiche en direct ce que filme l'iPhone.

Attention : `/dev/video42` correspond à la configuration de ce projet. Si le
numéro du device est modifié dans `start.sh`, il faut adapter la commande en
conséquence. `./start.sh --status` indique le device utilisé.

Cette étape suppose que VLC est installé. Si ce n'est pas le cas :

```bash
sudo pacman -S vlc
flatpak install flathub org.videolan.VLC
```

## Étape 3 — Détecter les visages

Dans un **second terminal** (le premier étant occupé par `make stream`) :

```bash
make detect
```

Une fenêtre s'ouvre et affiche le flux de l'iPhone. Chaque visage repéré est
entouré d'un carré vert, surmonté d'un nombre entre 0 et 1 : la confiance du
modèle. Le nombre de visages détectés est rappelé en haut à gauche.

La fenêtre s'ouvre à 1280 pixels de large (ou moins si l'écran est plus
petit), proportions du flux conservées. Elle est **librement redimensionnable**
à la souris, et la barre d'outils en bas de la fenêtre permet de zoomer et de
se déplacer dans l'image.

| Touche | Effet |
|--------|-------|
| `q` ou `Échap` | Quitte le script |
| `f` | Bascule en plein écran, et en ressort |

### Ce qui se passe réellement sur le système

Le script `detect.py` est un **lecteur de plus** de `/dev/video42`, au même
titre que VLC à l'étape 2. Le module v4l2loopback autorise plusieurs
applications à lire la même caméra virtuelle en même temps : Zoom ou OBS
peuvent donc continuer à s'en servir pendant que le script tourne. Rien n'est
réinjecté dans la caméra virtuelle — **les carrés n'apparaissent que dans la
fenêtre du script**, pas dans le flux vu par les autres logiciels.

Pour chaque image reçue, le script fait passer l'image dans **YuNet**, un petit
réseau de neurones fourni avec OpenCV (fichier `models/face_detection_yunet_2023mar.onnx`,
téléchargé par `install-deps.sh`). Pour chaque visage trouvé, YuNet renvoie :

- sa position et sa taille dans l'image — ce qui donne le carré ;
- cinq points de repère (yeux, nez, coins de la bouche), non affichés ici ;
- un **score de confiance** entre 0 et 1.

Ce score mesure à quel point le modèle est sûr qu'il s'agit bien d'un visage.
Ce n'est ni une mesure de la qualité de l'image, ni une identification de la
personne : le script détecte *qu'il y a* un visage, pas *à qui* il appartient.

Quelques réglages, en tête de `detect.py` :

- `SCORE_THRESHOLD` (0.6 par défaut) : en dessous de ce score, la détection est
  ignorée. L'augmenter réduit les faux positifs, mais fait rater les visages de
  profil ou mal éclairés.
- `VIDEO_DEVICE` (42) : à modifier en même temps que `start.sh` et le `Makefile`
  si le numéro du device change.
- `DISPLAY_WIDTH` (1280) : largeur de la fenêtre à l'ouverture. Elle n'a aucun
  effet sur la détection, uniquement sur l'affichage.

### Si l'image est floue une fois agrandie

Agrandir la fenêtre n'invente aucun détail : elle ne fait qu'étirer les pixels
reçus. Si l'image est floue, c'est que le flux lui-même est de faible
résolution.

Au lancement, le script affiche ce qui lui arrive réellement :

```
Flux 640x480 sur /dev/video42.
```

Si cette résolution est inférieure à `DISPLAY_WIDTH`, le script le signale
explicitement. Le réglage se fait alors **dans l'app OctoStream sur l'iPhone**
(qualité / résolution de diffusion), pas dans ce script ni dans le pipeline
GStreamer, qui se contentent de transporter ce que le téléphone envoie.

Le script s'arrête tout seul, avec un message, si le flux se coupe (par exemple
si `make stream` est interrompu par `Ctrl+C`).
