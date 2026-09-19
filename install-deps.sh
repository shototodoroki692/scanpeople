#!/usr/bin/env bash
# ============================================================================
# install-deps.sh
#
# Rôle : installer UNE SEULE FOIS tous les paquets nécessaires au projet.
# ============================================================================

# set -e : arrête le script au premier échec (installation propre ou rien)
# set -u : erreur si une variable non définie est utilisée
# set -o pipefail : un pipeline (cmd1 | cmd2) échoue si une seule commande
#                   à l'intérieur échoue, pas seulement la dernière
set -euo pipefail

# Vérifie qu'on n'exécute pas le script directement en root
# (sudo sera appelé explicitement là où c'est nécessaire, pas globalement)
if [[ "${EUID}" -eq 0 ]]; then
  echo "Ne lance pas ce script directement en root, utilise ton utilisateur normal."
  exit 1
fi

# Vérifie qu'on est bien sur Arch Linux (présence de pacman)
if ! command -v pacman &> /dev/null; then
  echo "Ce script est spécifique à Arch Linux (pacman introuvable)."
  exit 1
fi

# Rafraîchit la liste des paquets disponibles et met à jour les paquets avant
# d'installer les nouvelles dépendances.
echo "=== Mise à jour de la base de paquets ==="
sudo pacman -Syu

# 1.  Installation de v4l2loopback
#      
# NOTE
# v4l2loopback-dkms  : module noyau (compilé via DKMS pour ton noyau actuel)
#                      qui permettra de créer un device vidéo virtuel
# v4l2loopback-utils : utilitaires complémentaires pour ce module
# v4l-utils           : fournit v4l2-ctl, utile pour inspecter les devices
# --needed    : n'installe/ne touche pas un paquet déjà présent et à jour
# --noconfirm : pas de confirmation interactive (script automatisable)
echo "=== Installation de v4l2loopback ==="
sudo pacman -S --needed --noconfirm v4l2loopback-dkms v4l2loopback-utils v4l-utils

# 2.  Installation de linux-headers.
#
# linux-headers : nécessaire pour que DKMS puisse compiler v4l2loopback
# contre la version exacte de ton noyau actuel
echo "=== Installation de linux-header ==="
sudo pacman -S --needed --noconfirm linux-headers

# 3.  Installation de GStreamer.
#
# NOTE
# gstreamer        : cœur du framework de traitement de flux multimédia
# gst-plugins-base : éléments de base (conversion de formats vidéo, etc.)
# gst-plugins-good : éléments stables et bien maintenus
# gst-plugins-bad  : éléments moins stables mais souvent nécessaires
#                    (utile pour parser certains flux moins courants)
# gst-libav        : bindings vers ffmpeg/libav pour le décodage vidéo
echo "=== Installation de GStreamer et de ses plugins ==="
sudo pacman -S --needed --noconfirm \
  gstreamer \
  gst-plugins-base \
  gst-plugins-good \
  gst-plugins-bad \
  gst-libav

echo ""
echo "Installation terminée."
echo "Aucun module n'est chargé et aucune configuration persistante n'a été créée."
echo "Utilise start.sh à chaque session pour activer le device vidéo virtuel."