#!/usr/bin/env python3
# ============================================================================
# detect.py
#
# Role : lire le flux de la camera virtuelle /dev/video42 (alimentee par
# "make stream"), detecter les visages presents dans chaque image, et afficher
# le resultat dans une fenetre avec un carre et un score autour de chaque
# visage.
#
# Ce script ne modifie PAS le flux : v4l2loopback autorise plusieurs lecteurs
# simultanes, donc OBS/Zoom/VLC peuvent continuer a utiliser la camera
# virtuelle pendant que ce script l'analyse de son cote.
#
# Le detecteur utilise est YuNet, un petit reseau de neurones livre avec
# OpenCV. Pour chaque visage il renvoie sa position, 5 points de repere
# (yeux, nez, coins de la bouche) et un score de confiance entre 0 et 1.
# ============================================================================

import sys
from pathlib import Path

import cv2

# Numero du device video virtuel a lire.
# Doit rester coherent avec VIDEO_NR dans start.sh et VIDEO_DEVICE dans le Makefile.
VIDEO_DEVICE = 42

# Modele YuNet telecharge par install-deps.sh (~230 Ko)
MODEL_PATH = Path(__file__).parent / "models" / "face_detection_yunet_2023mar.onnx"

# En dessous de ce score, la detection est consideree comme trop incertaine
# et n'est pas affichee. Monter cette valeur = moins de faux positifs mais
# plus de visages rates.
SCORE_THRESHOLD = 0.6

# Seuil de la suppression des doublons (NMS) : quand plusieurs carres se
# superposent sur le meme visage, on ne garde que le meilleur.
NMS_THRESHOLD = 0.3

# Nombre maximum de detections gardees avant le filtrage NMS
TOP_K = 5000

# Largeur de la fenetre d'apercu a l'ouverture, en pixels. La hauteur suit
# automatiquement pour conserver les proportions de l'image. La fenetre reste
# librement redimensionnable a la souris : cette valeur n'est qu'un point de
# depart.
DISPLAY_WIDTH = 1280

# Nombre d'images a afficher avant d'appliquer ce redimensionnement.
# Qt n'honore resizeWindow() qu'une fois la fenetre reellement affichee a
# l'ecran, ce qui demande un cycle d'affichage complet (un imshow suivi d'un
# waitKey ne suffit pas) : demande trop tot, la consigne est ignoree et la
# fenetre garde la taille de l'image. Deux images suffisent, et a 30 images
# par seconde personne ne voit la difference.
RESIZE_DELAY_FRAMES = 2

# Couleurs au format BGR (et non RGB : c'est la convention d'OpenCV)
GREEN = (0, 255, 0)
BLACK = (0, 0, 0)

WINDOW_NAME = "scanpeople - detection de visages"


def open_camera():
    """Ouvre la camera virtuelle et renvoie la capture, ou termine le script
    avec un message explicite si le flux n'est pas disponible."""
    # CAP_V4L2 force le backend Video4Linux2 : sans ca, OpenCV peut choisir
    # un backend qui ne sait pas lire un device v4l2loopback.
    cap = cv2.VideoCapture(VIDEO_DEVICE, cv2.CAP_V4L2)

    if not cap.isOpened():
        sys.exit(
            f"Impossible d'ouvrir /dev/video{VIDEO_DEVICE}.\n"
            "La camera virtuelle n'existe pas encore : lance 'make stream'\n"
            "dans un autre terminal (elle la cree et l'alimente)."
        )

    # Le device peut exister tout en etant vide (personne n'ecrit dedans) :
    # dans ce cas l'ouverture reussit mais la premiere lecture echoue.
    ok, frame = cap.read()
    if not ok:
        cap.release()
        sys.exit(
            f"/dev/video{VIDEO_DEVICE} existe mais ne diffuse aucune image.\n"
            "Lance le streaming depuis l'iPhone (OctoStream), puis 'make stream'."
        )

    return cap, frame


def setup_window():
    """Cree la fenetre d'apercu, librement redimensionnable."""
    # Sans namedWindow explicite, cv2.imshow cree la fenetre en mode
    # WINDOW_AUTOSIZE : elle prend la taille exacte de l'image et devient
    # impossible a redimensionner. WINDOW_NORMAL fait l'inverse : la fenetre
    # est libre, et la barre d'outils Qt (en bas) propose un zoom.
    #
    # WINDOW_KEEPRATIO et WINDOW_GUI_EXPANDED valent tous les deux 0 dans
    # OpenCV : ce sont deja les comportements par defaut. On les ecrit quand
    # meme, pour que l'intention soit lisible — conserver les proportions et
    # garder la barre d'outils — mais ils n'ajoutent rien techniquement.
    cv2.namedWindow(
        WINDOW_NAME,
        cv2.WINDOW_NORMAL | cv2.WINDOW_KEEPRATIO | cv2.WINDOW_GUI_EXPANDED,
    )


def resize_window(width, height):
    """Donne a la fenetre DISPLAY_WIDTH pixels de large, proportions gardees.

    A n'appeler qu'une fois la fenetre affichee (voir RESIZE_DELAY_FRAMES) :
    demande plus tot, la consigne est purement et simplement ignoree.
    """
    # La hauteur se deduit du ratio reel du flux, jamais codee en dur : une
    # image 4:3 et une image 16:9 ne donnent pas la meme fenetre. Si l'ecran
    # est trop petit pour cette taille, le gestionnaire de fenetres la reduit
    # de lui-meme en conservant les proportions.
    cv2.resizeWindow(WINDOW_NAME, DISPLAY_WIDTH, round(height * DISPLAY_WIDTH / width))


def toggle_fullscreen():
    """Bascule la fenetre entre plein ecran et mode fenetre."""
    is_fullscreen = (
        cv2.getWindowProperty(WINDOW_NAME, cv2.WND_PROP_FULLSCREEN)
        == cv2.WINDOW_FULLSCREEN
    )
    cv2.setWindowProperty(
        WINDOW_NAME,
        cv2.WND_PROP_FULLSCREEN,
        cv2.WINDOW_NORMAL if is_fullscreen else cv2.WINDOW_FULLSCREEN,
    )


def draw_face(frame, face):
    """Dessine sur l'image le carre et le score d'un visage detecte.

    'face' est une ligne du tableau renvoye par YuNet :
    [x, y, largeur, hauteur, 10 coordonnees de points de repere, score]
    """
    x, y, w, h = face[:4].astype(int)
    score = float(face[-1])

    cv2.rectangle(frame, (x, y), (x + w, y + h), GREEN, 2)

    # Le score est affiche juste au-dessus du carre ; s'il n'y a pas la place
    # (visage colle au bord haut de l'image), on le place a l'interieur.
    label = f"{score:.2f}"
    label_y = y - 8 if y - 8 > 12 else y + h + 20
    cv2.putText(frame, label, (x, label_y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, GREEN, 2)


def main():
    if not MODEL_PATH.exists():
        sys.exit(
            f"Modele introuvable : {MODEL_PATH}\n"
            "Relance ./install-deps.sh pour le telecharger."
        )

    cap, frame = open_camera()
    height, width = frame.shape[:2]

    # La taille d'entree doit correspondre a la resolution reelle du flux,
    # sinon les coordonnees renvoyees ne tombent pas au bon endroit.
    detector = cv2.FaceDetectorYN.create(
        str(MODEL_PATH),
        "",
        (width, height),
        score_threshold=SCORE_THRESHOLD,
        nms_threshold=NMS_THRESHOLD,
        top_k=TOP_K,
    )

    setup_window()

    print(f"Flux {width}x{height} sur /dev/video{VIDEO_DEVICE}.")
    print("Touches : 'q' ou Echap pour quitter, 'f' pour le plein ecran.")

    # Agrandir la fenetre n'invente aucun detail : si la source est deja
    # petite, l'image sera simplement etiree et floue. Autant le dire tout de
    # suite plutot que de laisser chercher du cote du script.
    if width < DISPLAY_WIDTH:
        print(
            f"Note : le flux source est en {width}x{height}, plus petit que la "
            f"fenetre ({DISPLAY_WIDTH} px de large).\n"
            "       L'image sera donc etiree et un peu floue. La resolution se "
            "regle dans\n"
            "       l'app OctoStream sur l'iPhone, pas dans ce script."
        )

    # Compte a rebours avant d'appliquer la taille de la fenetre. Remis a sa
    # valeur de depart si la resolution du flux change en cours de route,
    # pour recalculer les proportions.
    resize_countdown = RESIZE_DELAY_FRAMES

    try:
        while True:
            # La premiere image a deja ete lue par open_camera() : on la traite
            # telle quelle, puis on lit la suivante en fin de boucle.
            h, w = frame.shape[:2]
            if (w, h) != (width, height):
                # La resolution du flux a change en cours de route
                width, height = w, h
                detector.setInputSize((width, height))
                resize_countdown = RESIZE_DELAY_FRAMES

            # detect() renvoie (code, tableau des visages). Quand aucun visage
            # n'est trouve, le tableau vaut None : ce cas doit etre gere,
            # sinon la boucle plante des que le champ est vide.
            _, faces = detector.detect(frame)
            faces = faces if faces is not None else []

            for face in faces:
                draw_face(frame, face)

            # Compteur en haut a gauche, double trace (noir puis vert) pour
            # rester lisible sur un fond clair comme sur un fond sombre.
            counter = f"Visages: {len(faces)}"
            cv2.putText(frame, counter, (12, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.8, BLACK, 4)
            cv2.putText(frame, counter, (12, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.8, GREEN, 2)

            cv2.imshow(WINDOW_NAME, frame)

            # waitKey(1) attend 1 ms une touche : c'est aussi ce qui laisse a
            # la fenetre le temps de se redessiner. 'q' ou Echap quittent,
            # 'f' bascule en plein ecran.
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break
            if key == ord("f"):
                toggle_fullscreen()

            # Mise a la taille voulue, une fois la fenetre bien affichee
            if resize_countdown > 0:
                resize_countdown -= 1
                if resize_countdown == 0:
                    resize_window(width, height)

            # Fenetre fermee a la croix : on sort proprement
            if cv2.getWindowProperty(WINDOW_NAME, cv2.WND_PROP_VISIBLE) < 1:
                break

            ok, frame = cap.read()
            if not ok:
                print("Le flux s'est arrete (make stream a ete coupe ?).")
                break
    except KeyboardInterrupt:
        print("\nInterrompu.")
    finally:
        # Libere le device et ferme la fenetre, meme en cas d'erreur ou de
        # Ctrl+C : sans ca, une fenetre fantome peut rester a l'ecran.
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
