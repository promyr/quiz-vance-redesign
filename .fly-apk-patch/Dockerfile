FROM registry.fly.io/quiz-vance-redesign-backend@sha256:2c2595879e8b3d43087b9cd0c0b44885032f7d62f9e77a49526711963b2428c0

COPY main.py /app/app/main.py
COPY quiz-vance-redesign-2.0.12+6-universal.apk /app/releases/android/quiz-vance-2.0.12.apk
COPY quiz-vance-redesign-2.0.12+6-universal.apk /app/releases/android/quiz-vance.apk

RUN python -m py_compile /app/app/main.py \
    && chmod 0755 \
    /app/releases/android/quiz-vance-2.0.12.apk \
    /app/releases/android/quiz-vance.apk
