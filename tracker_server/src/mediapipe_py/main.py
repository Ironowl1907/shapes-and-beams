import cv2
import socket
import struct
import time
import subprocess
import threading

from mediapipe_py.landmarker import Landmarker

import os
import sys

# Qt: forzar X11/XWayland (la ventana del tracker se usa para cerrar con q/ESC).
os.environ.setdefault("QT_QPA_PLATFORM", "xcb")
# Quitar el parpadeo / warnings de TF cuando corre como hijo del juego.
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("GLOG_minloglevel", "2")

STATUS_FILE = ".tracker.status"   # mismo archivo de fase que lee el juego
# Sin ventana: el juego (fullscreen) lo lanza headless; a mano se corre con
# ventana para verse. El launcher pasa --headless o pone TRACKER_HEADLESS=1.
HEADLESS = os.environ.get("TRACKER_HEADLESS", "0") == "1" or "--headless" in sys.argv

UDP_IP = "127.0.0.1"
UDP_PORT = 5005

# ---- Config de camara (override por env, ej: TRACKER_CAM_WIDTH=640) ----
# Camara USB2.0 (Shinetech FHD): modos reales MJPG hasta 1920x1080 SOLO a
# 30/15fps (no hay 1080p60). En esta sala el auto-exposure llega a bajarla a
# ~17fps; la clave para 30fps estables es:
#   1) exposure_dynamic_framerate=0 (v4l2-ctl, ANTES de abrir)
#   2) BUFFERSIZE=2 (con 1 el driver se degrada a ~14fps)
#   3) captura en su propio hilo (la inferencia MediaPipe ~21ms no frena el bus)
CAM_WIDTH = int(os.environ.get("TRACKER_CAM_WIDTH", "1280"))
CAM_HEIGHT = int(os.environ.get("TRACKER_CAM_HEIGHT", "720"))
CAM_FPS = int(os.environ.get("TRACKER_CAM_FPS", "30"))
CAM_INDEX = int(os.environ.get("TRACKER_CAM_INDEX", "0"))
V4L2_DEV = f"/dev/video{CAM_INDEX}"


def _write_status(fase: str) -> None:
    try:
        with open(STATUS_FILE, "w") as f:
            f.write(fase)
    except OSError:
        pass


def _v4l2_set(*args: str) -> subprocess.CompletedProcess:
    """Ejecuta v4l2-ctl sobre el device del tracker (best-effort)."""
    try:
        return subprocess.run(
            ["v4l2-ctl", "-d", V4L2_DEV, *args],
            capture_output=True, text=True, timeout=2
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"v4l2-ctl fallo (ignorado): {e}", flush=True)
        return subprocess.CompletedProcess(args, 1)


def _open_camera():
    # Clave #1: exposure_dynamic_framerate=0. Con el default (1) la camara
    # ralentiza el fps para alargar la exposicion en salas oscuras (~17fps).
    _v4l2_set("--set-ctrl=exposure_dynamic_framerate=0")
    # Clave #2: MJPG (YUYV a 720p solo da 5fps) + BUFFERSIZE=2 (con 1 el
    # driver se degrada a ~14fps en este firmware).
    cap = cv2.VideoCapture(CAM_INDEX, cv2.CAP_V4L2)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAM_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAM_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, CAM_FPS)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 2)
    return cap


def main() -> None:
    """Tracker real: abre la cámara y manda los 21 landmarks por UDP a 5005."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    landmarker = Landmarker()
    landmarker.init()

    cap = _open_camera()
    if not cap.isOpened():
        print("ERROR: no se pudo abrir la cámara %s" % V4L2_DEV, flush=True)
        _write_status("error:camera")
        return
    rw, rh, rfps = cap.get(3), cap.get(4), cap.get(5)
    print("camara: pedida %dx%d@%d -> real %.0fx%.0f@%.0ffps" % (
        CAM_WIDTH, CAM_HEIGHT, CAM_FPS, rw, rh, rfps), flush=True)

    # Hilo de captura dedicado: cap.read() corre siempre a tope aunque la
    # inferencia MediaPipe tarde; el loop principal toma el frame mas nuevo.
    latest = {"seq": 0, "ok": True, "frame": None}

    def _grab() -> None:
        seq = 0
        while latest["ok"] and cap.isOpened():
            ok, frame = cap.read()
            if not ok:
                latest["ok"] = False
                break
            seq += 1
            latest["seq"] = seq
            latest["frame"] = frame

    grabber = threading.Thread(target=_grab, daemon=True)
    grabber.start()
    # Esperar el primer frame (la camara puede tardar ~1s en arrancar).
    for _ in range(150):  # ~3s max
        if latest["seq"] > 0:
            break
        time.sleep(0.02)
    if latest["seq"] == 0:
        print("ERROR: la camara no entrega frames", flush=True)
        _write_status("error:camera")
        latest["ok"] = False
        grabber.join(timeout=2)
        cap.release()
        return

    _write_status("ready")
    # Heartbeat: reescribe el status cada 2s para que el juego sepa que el
    # tracker sigue vivo (usa la frescura del archivo, multiplataforma).
    last_hb = time.time()

    last_seq = 0
    while latest["ok"] and cap.isOpened():
        if latest["seq"] == last_seq:
            time.sleep(0.002)   # sin frame nuevo: no quemar CPU
            continue
        if time.time() - last_hb > 2.0:
            _write_status("ready")
            last_hb = time.time()
        last_seq = latest["seq"]
        image = latest["frame"]

        # Convert to RGB for inference
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        rgb_image.flags.writeable = False

        landmarks_result = landmarker.process(rgb_image)

        # Process landmarks and network payload
        if landmarks_result:
            packed_landmarks = []
            for lm in landmarks_result:
                packed_landmarks.extend([lm[0], lm[1], lm[2]])

                # Draw landmark (assuming normalized coordinates 0.0 - 1.0)
                h, w, _ = image.shape
                cx, cy = int(lm[0] * w), int(lm[1] * h)
                cv2.circle(image, (cx, cy), 3, (0, 255, 0), -1)

            payload = struct.pack(
                f"<i{len(packed_landmarks)}f",
                len(landmarks_result),
                *packed_landmarks
            )

            sock.sendto(payload, (UDP_IP, UDP_PORT))
        else:
            payload = struct.pack(
                f"<i",
                0,
            )
            sock.sendto(payload, (UDP_IP, UDP_PORT))

        # Ventana de debug (solo manual: el juego lo lanza headless porque
        # es fullscreen y la ventana OpenCV taparía todo).
        if not HEADLESS:
            cv2.imshow("Landmark Tracking", cv2.flip(image, 1))
            # Press 'q' or ESC to exit
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27:
                break

    landmarker.shutdown()
    cap.release()
    cv2.destroyAllWindows()
    sock.close()


if __name__ == "__main__":
    main()
