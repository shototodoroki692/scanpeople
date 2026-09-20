# ============================================================================
# Makefile — point d'entrée du projet.
#
#   make stream   crée le device vidéo virtuel /dev/video42 (via start.sh) puis
#                 lance le pipeline GStreamer qui y relie le flux RTSP de
#                 l'iPhone (via OctoStream)
#   make detect   affiche le flux avec un carré autour de chaque visage détecté
# ============================================================================

# "-include" charge le fichier .env s'il existe (le "-" évite une erreur
# si le fichier est absent). Chaque ligne du type VAR=valeur y devient
# une variable Makefile utilisable plus bas.
-include .env

# Port RTSP par défaut d'OctoStream (à ajuster si l'app en affiche un autre ;
# Surcharge possible avec la commande : PORT=xxxx make stream)
PORT ?= 554

# Nom de l'endpoint exposé par OctoStream sur le serveur RTSP
ENDPOINT := stream

# Device vidéo virtuel créé par v4l2loopback (start.sh)
VIDEO_DEVICE := /dev/video42

# Construit l'URL RTSP complète à partir des variables ci-dessus
RTSP_URL := rtsp://$(IPHONE_IP):$(PORT)/$(ENDPOINT)

# .PHONY : indique que ces noms ne sont pas des fichiers à produire, mais bien
# des commandes à exécuter (évite un conflit si un fichier nommé "stream" existe)
.PHONY: camera stream detect

# Cible intermédiaire : s'assure que la caméra virtuelle /dev/video42 existe
# avant qu'on essaie d'écrire dedans. start.sh est idempotent — relancé alors
# que le device existe déjà, il se contente de le signaler — donc on peut
# l'appeler à chaque "make stream" sans risque.
#
# Note : start.sh charge un module noyau, il demandera donc le mot de passe
# sudo la première fois après chaque démarrage de la machine.
camera:
	@./start.sh

# Cible principale : crée la caméra virtuelle si besoin (dépendance "camera"),
# puis lance le pipeline GStreamer qui l'alimente
stream: camera
	@# Vérifie que IPHONE_IP a bien été fournie avant de lancer quoi que ce
	@# soit ; sinon, affiche une erreur claire plutôt que de laisser
	@# gst-launch échouer avec un message obscur.
	@test -n "$(IPHONE_IP)" || { echo "IPHONE_IP n'est pas défini (voir .env)."; exit 1; }
	@echo "Connexion au flux : $(RTSP_URL)"
	gst-launch-1.0 \
		rtspsrc location=$(RTSP_URL) latency=0 ! \
		rtph264depay ! \
		h264parse ! \
		avdec_h264 ! \
		videoconvert ! \
		v4l2sink device=$(VIDEO_DEVICE)

# Cible secondaire : analyse le flux de la caméra virtuelle et affiche un
# carré autour de chaque visage détecté, avec son score de confiance.
# À lancer dans un autre terminal, pendant que "make stream" tourne.
detect:
	@echo "Détection de visages sur $(VIDEO_DEVICE) — 'q' pour quitter"
	python3 detect.py
