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

  ```
  IPHONE_IP=192.168.1.42
  ```

  (remplace par l'adresse affichée par l'app sur l'iPhone)

## Récapitulatif

| Étape | Commande | Effet sur le système |
|-------|----------|----------------------|
| 1 | `./start.sh` | Crée une fausse webcam vide : `/dev/video42` |
| 2 | `make stream` | Y déverse en direct la vidéo de l'iPhone |
| 3 | `vlc v4l2:///dev/video42` | Affiche le résultat pour vérifier |

Une fois les étapes 1 et 2 lancées, n'importe quelle application vidéo peut
sélectionner « iPhone Virtual Camera » dans sa liste de caméras.

## Étape 1 — Créer la caméra virtuelle

```bash
./start.sh
```

### Ce qui se passe réellement sur le système

Sous Linux, chaque caméra est représentée par un fichier spécial dans
`/dev/` : une vraie webcam USB apparaît par exemple comme `/dev/video0`.
Les logiciels vidéo ne savent lire que ce genre de fichier.

Le problème : l'iPhone n'est pas branché en USB, il envoie sa vidéo par le
réseau. Il n'existe donc aucun `/dev/videoX` qui lui corresponde.

`start.sh` règle ça en chargeant dans le noyau Linux un module appelé
**v4l2loopback**. Ce module crée une **fausse caméra** — une caméra qui
n'existe pas physiquement, mais que le système traite exactement comme une
vraie. Concrètement, après avoir lancé le script :

- un nouveau fichier `/dev/video42` apparaît sur la machine ;
- il porte le nom « iPhone Virtual Camera » dans les applications ;
- pour l'instant il est **vide** : la caméra existe, mais personne ne lui
  envoie encore d'image.

Le numéro 42 est choisi volontairement haut pour ne pas entrer en conflit
avec une vraie webcam déjà présente.

Quelques précisions utiles :

- Le script demande le **mot de passe sudo** : charger un module dans le
  noyau est une opération système, elle nécessite les droits administrateur.
- **Rien n'est écrit sur le disque.** La caméra virtuelle vit uniquement en
  mémoire, elle disparaît au redémarrage de l'ordinateur. Il faut donc
  relancer `./start.sh` une fois après chaque démarrage de la machine.
- Relancer le script alors que la caméra existe déjà ne fait rien de plus :
  il le signale et s'arrête.

Deux options supplémentaires :

```bash
./start.sh --status   # la caméra virtuelle est-elle active ?
./start.sh --stop     # supprime la caméra virtuelle
```

`--stop` échoue volontairement si une application est en train d'utiliser la
caméra, pour éviter de couper un flux en cours par accident.

## Étape 2 — Brancher l'iPhone sur la caméra virtuelle

Lance d'abord le streaming dans l'app OctoStream sur l'iPhone, puis, sur
l'ordinateur :

```bash
make stream
```

### Ce qui se passe réellement sur le système

L'app sur l'iPhone diffuse la vidéo sur le réseau local, à une adresse du
type `rtsp://<IP_de_l_iPhone>:554/stream`. C'est un flux réseau : sans rien
de plus, l'ordinateur peut le recevoir, mais aucune application vidéo ne
saura le considérer comme une caméra.

`make stream` lance **GStreamer**, un outil qui joue le rôle de tuyau entre
les deux mondes. Il :

1. se connecte au flux vidéo de l'iPhone sur le réseau ;
2. décompresse les images (elles arrivent compressées en H.264) ;
3. les écrit en continu dans `/dev/video42`, la caméra virtuelle créée à
   l'étape 1.

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
  make stream
  ```

## Étape 3 — Vérifier que l'image arrive bien

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
```