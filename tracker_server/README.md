# tracker_server — MediaPipe hand tracker (UDP)

Servicio Python que captura la cámara, detecta los 21 landmarks de la mano
con MediaPipe + OpenCV y los envía por **UDP a `127.0.0.1:5005`**.

- Lo consume `scripts/HandTrackingClient.gd` (autoload de Godot), que expone
  `has_hand`, `get_palm_center()` y `get_hand_angle_deg()` para mover y rotar
  la nave. Puño cerrado = escudo.
- Sin datos del tracker, el juego cae automáticamente a teclado (flechas /
  WASD): siempre jugable, con mano o sin ella.
- El juego lo levanta solo al abrirse (`run_tracker.sh --detach`, sin
  duplicarlo si ya corre) y lo apaga al cerrarse.

## Instalación única

```bash
cd tracker_server && uv sync   # descarga mediapipe y opencv (Python ≥ 3.12, uv)
```

En Windows: doble clic en `setup_tracker.bat` (hace lo mismo + instala `uv` si falta).

## Cómo sabe el juego si estoy vivo

`main.py` reescribe `.tracker.status` cada 2 segundos (heartbeat). El juego
(`HandTrackingClient`) lo considera vivo si el archivo tiene menos de 5
segundos — multiplataforma, sin depender de PIDs. Los launchers
(`run_tracker.sh` / `run_tracker.bat`) además evitan duplicados y cierran el
tracker cuando muere el juego (watchdog por PID + bandera `.tracker.game_exit`).

## Correr a mano

```bash
./run_tracker.sh            # primer plano (ventana de tracking visible)
./run_tracker.sh --detach   # segundo plano (como lo levanta el juego)
```

Requiere webcam (`/dev/video0`). Solo habla con esta máquina (`127.0.0.1`).
