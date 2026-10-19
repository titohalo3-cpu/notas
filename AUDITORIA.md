# Auditoría de `sin-revisar/`

Fecha: 19/10/2026. Entorno: Docker 29.8.0, Compose v5.5.1, Windows 11.

## 1. Informe del agente (puntos señalados)

1. Usa `python:latest` en lugar de una versión fija; la imagen resultante es
   enorme.
2. Instala `vim`, `git`, `curl` y `build-essential` sin necesidad.
3. Ejecuta como `root` porque no hay `USER`.
4. `CLAVE_ADMIN=admin1234` está grabada en la imagen con `ENV` y también en el
   compose; se puede leer desde fuera.
5. Arranca con `python app.py`, el servidor de desarrollo de Flask, con
   `debug=True`.
6. Redis publica el puerto 6379 al exterior.
7. Redis no tiene volumen: las notas se pierden al recrear el contenedor.
8. No hay healthcheck ni espera real a que Redis esté sano.
9. `COPY . .` antes de `pip install` rompe la caché en cada cambio.
10. Sin `.dockerignore`, se copian `.git` y `.env` dentro de la imagen.
11. La imagen tarda una eternidad en arrancar por instalar `vim` y `git`.

## 2. Verificación con comandos

| # | Problema señalado | ¿Es cierto? (evidencia) | Gravedad | Corrección |
|---|---|---|---|---|
| 1 | `python:latest` | **Sí.** `docker image inspect notas-malo` muestra `PYTHON_VERSION=3.15.0`; `docker image ls` da 1,85 GB (477 MB de contenido) frente a 191 MB de la buena. | Alta | `FROM python:3.12-slim`. |
| 2 | Paquetes innecesarios | **Sí.** El build instala 18 paquetes nuevos y 93,4 MB adicionales (`vim`, `git`, `curl`, `build-essential`). | Media | No instalar nada extra; healthcheck con `urllib`. |
| 3 | Usuario root | **Sí.** `docker run --rm notas-malo id` → `uid=0(root) gid=0(root)`. | Alta | `groupadd/useradd` + `USER app`. La versión buena responde `uid=999(app)`. |
| 4 | `CLAVE_ADMIN` legible | **Sí.** `docker image inspect notas-malo --format '{{json .Config.Env}}'` incluye `"CLAVE_ADMIN=admin1234"`; `docker run --rm notas-malo printenv CLAVE_ADMIN` imprime `admin1234`. | Alta | Sacarla de la imagen; en la buena va en `.env` → `environment` de Compose y `.env` está en `.dockerignore`. |
| 5 | Servidor de desarrollo | **Sí.** `curl -i localhost:8001/salud` responde `Server: Werkzeug/3.1.9 Python/3.15.0`; los logs dicen `Debug mode: on` y `Debugger is active!`. | Alta | `gunicorn` con `CMD` JSON; la buena responde `Server: gunicorn`. |
| 6 | Redis publicado | **Sí.** `sin-revisar/docker-compose.yml` tiene `ports: - "6379:6379"`. | Alta | Quitar `ports`; solo red interna de Compose. |
| 7 | Sin volumen | **Sí.** El compose inseguro no declara `volumes`; al recrear el contenedor se pierde el AOF. | Alta | `redis-data:/data` + `--appendonly yes`. |
| 8 | Sin healthcheck | **Sí.** Ni el Dockerfile ni el compose inseguros declaran `healthcheck`; `docker compose ps` mostraría solo `Up`, no `healthy`. | Media | Healthcheck en web y cache + `depends_on: condition: service_healthy`. |
| 9 | Caché rota | **Sí.** `COPY . .` va antes de `RUN pip install`; cualquier cambio en `app.py` invalida la instalación. | Media | Copiar primero `requirements.txt` e instalar; después el código. |
| 10 | `.git` y `.env` dentro de la imagen | **No en esta build.** `docker run --rm notas-malo ls -a /app` muestra `Dockerfile`, `docker-compose.yml`, `app.py`, `requirements.txt`, `templates` y `.dockerignore`, pero **no** `.git` ni `.env`: el `.dockerignore` de la raíz también se aplica al construir con `-f sin-revisar/Dockerfile`. Sí se copian los ficheros de build, que no deberían estar. | Baja (en este caso) | Mantener `.dockerignore` y construir la versión insegura en un contexto aislado si se quiere reproducir el fallo. |
| 11 | Arranque lentísimo por `vim`/`git` | **Exagerado.** El contenedor arranca en segundos; lo que crece es el tamaño y la superficie de ataque, no el tiempo de arranque. | Informativa | El tamaño se corrige con la imagen slim y sin paquetes extra. |

## 3. Punto falso o exagerado del informe

- **Falso en esta práctica:** «sin `.dockerignore` se copian `.git` y `.env`
  dentro de la imagen». Al construir con `docker build -f
  sin-revisar/Dockerfile -t notas-malo .`, Docker usa el `.dockerignore` de la
  raíz del contexto, que excluye `.git` y `.env`. La evidencia es
  `docker run --rm notas-malo ls -a /app`, donde no aparecen. El riesgo existe
  si se construye desde otra carpeta o si se elimina ese `.dockerignore`, pero
  no es lo que ocurre con el comando de la práctica.
- **Exagerado:** «tarda una eternidad en arrancar». El arranque es inmediato;
  el problema real es el tamaño (1,85 GB) y los paquetes de más.

## 4. Conclusión

La versión `sin-revisar/` acumula problemas de tamaño, privilegios, secretos y
servidor de aplicación. La versión de la raíz corrige los cinco bloques:
imagen fijada y slim, usuario sin privilegios, gunicorn, secretos fuera de la
imagen, Redis sin puertos con volumen y healthchecks.
