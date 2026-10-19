# Tablón de notas — despliegue con Docker Compose

Aplicación Flask que guarda notas en Redis. Este repositorio contiene la
contenerización de producción, una versión deliberadamente insegura para la
auditoría (`sin-revisar/`) y la documentación de la práctica.

## 1. Requisitos

- Docker Engine 24 o superior con el plugin Compose v2
  (`docker --version` y `docker compose version`).
- Puerto **8000** libre en el equipo anfitrión. Si está ocupado, cambia la
  publicación en `docker-compose.yml` (`"8001:8000"`) y usa ese puerto en las
  comprobaciones.
- No hace falta Python ni Redis instalados en el equipo: todo se ejecuta en
  contenedores.
- Git, solo si vas a clonar el repositorio.

## 2. Variables de entorno

| Variable | Obligatoria | Valor por defecto | Dónde se define | Uso |
|---|---|---|---|---|
| `CLAVE_ADMIN` | Sí | — | `.env` → interpolada en `docker-compose.yml` | Clave de administración. La aplicación de ejemplo no la consume, pero se mantiene fuera de la imagen. |
| `TITULO_APP` | No | `Tablón de notas` | `.env` o `docker-compose.yml` | Título visible en la portada. |
| `REDIS_URL` | No | `redis://localhost:6379` | `docker-compose.yml` | Conexión a Redis. En Compose vale `redis://cache:6379/0`. |

Crea el fichero `.env` a partir del ejemplo y cambia la clave:

```bash
cp .env.example .env
# edita .env y pon una CLAVE_ADMIN propia
```

`.env` está en `.gitignore` y en `.dockerignore`: **no se versiona ni se copia
dentro de la imagen**. Si falta, Compose se detiene con un error explícito
gracias a `${CLAVE_ADMIN:? ...}`.

## 3. Puesta en marcha

Desde la raíz del proyecto:

```bash
docker compose up -d --build
docker compose ps
```

`web` espera a que `cache` esté `healthy` (`depends_on: condition:
service_healthy`) y después arranca gunicorn en el puerto 8000.

Comprobación rápida:

```bash
curl -s http://localhost:8000/salud
# {"estado":"ok","notas":0}
```

Abre <http://localhost:8000> en el navegador.

Para cambiar el puerto publicado, edita `docker-compose.yml`:

```yaml
ports:
  - "8001:8000"
```

## 4. Pruebas de comprobación

```bash
# 1. Estado y salud de los servicios
docker compose ps

# 2. La aplicación responde y Redis está disponible
curl -s http://localhost:8000/salud

# 3. Alta de una nota (302 y redirección a la portada)
curl -i -X POST -d "texto=Nota de prueba" http://localhost:8000/notas

# 4. La nota aparece en la portada
curl -s http://localhost:8000/ | grep "Nota de prueba"

# 5. El contenedor no corre como root
docker compose exec web id
# uid=999(app) gid=999(app)

# 6. Secretos y Git fuera de la imagen
docker compose exec web ls -a /app
# .  ..  app.py  requirements.txt  templates
```

### Persistencia

Redis escribe con AOF (`--appendonly yes`) sobre el volumen nombrado
`notas_redis-data`. Para comprobarlo:

```bash
curl -s -X POST -d "texto=Persistente" http://localhost:8000/notas
docker compose restart
curl -s http://localhost:8000/salud      # notas: 1
```

Al borrar el volumen, los datos desaparecen:

```bash
docker compose down -v
docker compose up -d
curl -s http://localhost:8000/salud      # notas: 0
```

## 5. Dónde quedan los datos

- **Notas:** en Redis, dentro del volumen Docker `notas_redis-data`
  (nombre explícito definido en Compose). Redis guarda `/data/appendonly.aof`.
- **Configuración:** `.env` en el equipo anfitrión, fuera de la imagen.
- **Código:** dentro de la imagen, en `/app`; el contenedor es efímero.
- Para inspeccionar el volumen:

```bash
docker volume inspect notas_redis-data
docker compose exec cache redis-cli LRANGE notas 0 -1
```

## 6. Cómo ver los registros

```bash
# Todos los servicios, en primer plano
docker compose logs -f

# Solo la aplicación
docker compose logs -f web

# Solo Redis
docker compose logs -f cache

# Últimas 100 líneas sin seguir
docker compose logs --tail=100
```

Gunicorn escribe los accesos y errores a la salida estándar
(`--access-logfile - --error-logfile -`), por lo que `docker compose logs`
muestra todo.

## 7. Cómo parar y limpiar

```bash
# Parar y eliminar contenedores y red (conserva el volumen y las notas)
docker compose down

# Parar y eliminar también el volumen (borra las notas)
docker compose down -v

# Eliminar la imagen construida
docker image rm notas-web:latest

# Limpieza opcional de recursos no usados
docker system prune
```

## 8. Estructura del proyecto

```text
notas/
├── app.py                  # aplicación Flask
├── requirements.txt        # Flask, redis, gunicorn (versiones fijadas)
├── templates/index.html    # plantilla de la portada
├── Dockerfile              # imagen de producción
├── .dockerignore           # excluye .git, .env, sin-revisar y documentación
├── docker-compose.yml      # servicios web + cache
├── .env.example            # plantilla de variables
├── README.md               # este documento
├── prompts.md              # registro de prompts de la práctica
└── sin-revisar/            # versión insegura, solo para el ejercicio de auditoría
```

## 9. Decisiones de seguridad y tamaño

- Imagen base fijada: `python:3.12-slim` (no `latest`).
- Dependencias en una capa anterior al código para aprovechar la caché.
- Usuario de sistema `app` (UID/GID 999), sin shell de login ni home
  escribible; el proceso no corre como root.
- `EXPOSE 8000` documenta el puerto; la publicación real se hace en Compose.
- `HEALTHCHECK` contra `/salud` usando la librería estándar de Python (sin
  instalar `curl`).
- Arranque con gunicorn (2 workers) y `CMD` en formato JSON.
- Redis no publica puertos: solo es accesible desde la red interna de Compose.
- Redis tiene healthcheck, persistencia AOF y volumen nombrado.
- `.env` y `.git` nunca entran en la imagen.

## 10. Auditoría de la versión `sin-revisar/`

La imagen insegura se construye **solo para comparar**:

```bash
docker build -f sin-revisar/Dockerfile -t notas-malo .
docker image ls
docker run --rm notas-malo id
docker image inspect notas-malo --format '{{json .Config.Env}}'
docker run --rm notas-malo printenv CLAVE_ADMIN
```

Resultados esperados: imagen de ~1,85 GB, usuario `root`, `CLAVE_ADMIN`
grabada en la imagen, servidor de desarrollo Flask con `debug=True` y Redis
publicado en el puerto 6379. El informe completo está en la memoria de la
práctica.
