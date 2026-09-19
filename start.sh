#!/usr/bin/env bash
# ============================================================================
# start.sh
#
# Rôle : à lancer manuellement, une fois par session (après chaque boot),
# pour activer le device vidéo virtuel qui recevra le flux de l'iPhone.
#
# Contrairement à une configuration écrite dans /etc/modprobe.d/, ce script
# passe les options directement en ligne de commande à modprobe : rien n'est
# écrit sur le disque, donc rien ne persiste après un redémarrage.
# Le module reste chargé jusqu'à ce que tu le décharges explicitement
# (via ce script avec l'option --stop) ou que tu redémarres la machine.
#
# Une fois ce script exécuté, le device /dev/videoX est prêt : il ne te
# reste plus qu'à lancer l'app de streaming sur l'iPhone et à connecter
# le pipeline GStreamer sur son URL websocket.
# ============================================================================

set -euo pipefail

# Numéro du device vidéo virtuel à créer (/dev/video42)
# Choisi volontairement haut pour éviter un conflit avec une vraie webcam
readonly VIDEO_NR=42

# Nom affiché du device dans les applications vidéo (OBS, Zoom, etc.)
readonly CARD_LABEL="iPhone Virtual Camera"

# Petite fonction d'aide affichant comment utiliser le script
usage() {
  echo "Usage :"
  echo "  $0            # active le device vidéo virtuel"
  echo "  $0 --stop     # désactive le device (décharge le module)"
  echo "  $0 --status   # affiche si le device est actif ou non"
}

# Fonction qui vérifie si le module v4l2loopback est actuellement chargé
is_loaded() {
  # lsmod liste les modules chargés ; grep -q cherche "v4l2loopback" sans
  # afficher de sortie (silencieux), et renvoie un code succès/échec
  lsmod | grep -q v4l2loopback
}

# Fonction qui décharge le module (coupe le device virtuel)
stop_camera() {
  if is_loaded; then
    echo "Désactivation du device vidéo virtuel..."
    # rmmod via modprobe -r : décharge le module (échoue si le device
    # est encore utilisé par une application, ce qui est volontaire :
    # on ne veut pas couper un flux en cours d'utilisation par erreur)
    sudo modprobe -r v4l2loopback
    echo "Device désactivé."
  else
    echo "Le device n'était pas actif."
  fi
}

# Fonction qui affiche l'état actuel du module
show_status() {
  if is_loaded; then
    echo "Le device vidéo virtuel est actif."
    # Affiche les détails du device si l'outil v4l2-ctl est disponible
    if command -v v4l2-ctl &> /dev/null; then
      v4l2-ctl --device "/dev/video${VIDEO_NR}" --info
    fi
  else
    echo "Le device vidéo virtuel n'est pas actif."
  fi
}

# Fonction qui active le device vidéo virtuel pour cette session
start_camera() {
  # Si le module est déjà chargé, on ne fait rien de plus : les options
  # d'un module déjà en mémoire ne peuvent pas être changées à chaud
  if is_loaded; then
    echo "Le device vidéo virtuel est déjà actif."
    show_status
    return 0
  fi

  echo "Activation du device vidéo virtuel /dev/video${VIDEO_NR}..."
  # Charge le module avec les options passées directement en ligne de
  # commande (rien n'est écrit dans /etc/modprobe.d/, donc rien ne
  # persistera après un redémarrage)
  #   video_nr=${VIDEO_NR}      -> force le numéro du device créé
  #   card_label="${CARD_LABEL}" -> nom affiché dans les applications
  #   exclusive_caps=1          -> requis pour que Chrome/OBS/Zoom
  #                                reconnaissent correctement le device
  sudo modprobe v4l2loopback \
    video_nr="${VIDEO_NR}" \
    card_label="${CARD_LABEL}" \
    exclusive_caps=1

  echo "Device activé : /dev/video${VIDEO_NR}"
  echo ""
  echo "Prochaine étape : lance l'app de streaming sur ton iPhone, connecte-la"
  echo "au même réseau Wi-Fi que cette machine, et utilise l'URL websocket"
  echo "affichée par l'app pour démarrer ton pipeline GStreamer."
}

# ----------------------------------------------------------------------------
# Point d'entrée du script : lit le premier argument passé pour décider
# quelle action effectuer
# ----------------------------------------------------------------------------
case "${1:-}" in
  --stop)
    stop_camera
    ;;
  --status)
    show_status
    ;;
  "")
    # Aucun argument : comportement par défaut, on active le device
    start_camera
    ;;
  *)
    usage
    exit 1
    ;;
esac