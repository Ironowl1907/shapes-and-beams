import cv2
import mediapipe as mp
import numpy as np
from numpy._typing import ArrayLike


class Landmarker:
    def __init__(self) -> None:
        pass

    def init(self):
        self.hands_solution = mp.solutions.hands

        self.hands = self.hands_solution.Hands(
            model_complexity=0,   # lite: ~21ms/frame @720p, mas robusto en frames con ruido
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )

    def process(self, image: cv2.typing.MatLike) -> ArrayLike:
        results = self.hands.process(image)

        if not results.multi_hand_landmarks:
            return []

        hand_landmarks = results.multi_hand_landmarks[0]

        landmarks_coords = [
            (nl.x, nl.y, nl.z)
            for nl in hand_landmarks.landmark
        ]
        return landmarks_coords

    def shutdown(self):
        self.hands.close()
