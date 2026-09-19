# ============================================================================
# Makefile — lance le pipeline GStreamer qui relie le flux RTSP de l'iPhone
# (via OctoStream) au device vidéo virtuel /dev/video42.
# ============================================================================

# "-include" charge le fichier .env s'il existe (le "-" évite une erreur
# si le fichier est absent). Chaque ligne du type VAR=valeur y devient
# une variable Makefile utilisable plus bas.
-include .env

# Vérifie que la variable d'environnement IPHONE_IP a bien été fournie
# avant de lancer quoi que ce soit ; sinon, affiche une erreur claire
# plutôt que de laisser gst-launch échouer avec un message obscur.
ifndef IPHONE_IP
$(error IPHONE_IP n'est pas défini.)
endif

# Port RTSP par défaut d'OctoStream (à ajuster si l'app en affiche un autre ;
# Surcharge possible avec la commande : PORT=xxxx make stream)
PORT ?= 554

# Nom de l'endpoint exposé par OctoStream sur le serveur RTSP
ENDPOINT := stream

# Device vidéo virtuel créé par v4l2loopback (start.sh)
VIDEO_DEVICE := /dev/video42

# Construit l'URL RTSP complète à partir des variables ci-dessus
RTSP_URL := rtsp://$(IPHONE_IP):$(PORT)/$(ENDPOINT)

# .PHONY : indique que "stream" n'est pas un fichier à produire, mais bien
# une commande à exécuter (évite un conflit si un fichier nommé "stream" existe)
.PHONY: stream

# Cible principale : lance le pipeline GStreamer
stream:
	@echo "Connexion au flux : $(RTSP_URL)"
	gst-launch-1.0 \
		rtspsrc location=$(RTSP_URL) latency=0 ! \
		rtph264depay ! \
		h264parse ! \
		avdec_h264 ! \
		videoconvert ! \
		v4l2sink device=$(VIDEO_DEVICE)