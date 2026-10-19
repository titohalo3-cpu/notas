# syntax=docker/dockerfile:1
FROM python:3.12-slim

# Salida sin búfer y sin ficheros .pyc dentro del contenedor.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Las dependencias se copian e instalan antes que el código para aprovechar
# la caché de capas: si solo cambia app.py, esta capa no se reconstruye.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Usuario de sistema sin privilegios, sin shell de login ni home escribible.
RUN groupadd --system app \
    && useradd --system --gid app --no-create-home --home-dir /app \
       --shell /usr/sbin/nologin app

# El código se copia ya con el propietario final.
COPY --chown=app:app app.py ./
COPY --chown=app:app templates ./templates

USER app

EXPOSE 8000

# Healthcheck sin dependencias extra: usa la librería estándar de Python.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/salud', timeout=2).status == 200 else 1)"]

# Gunicorn es un servidor WSGI de producción; nunca el servidor de desarrollo.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
