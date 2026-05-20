# Manual de administracion

RA3 - Despliegue de Aplicaciones Web (2º DAW)

## Gestion diaria

Comandos basicos:

```bash
docker compose ps                          # estado de los servicios
docker compose logs -f                     # logs en vivo (todos)
docker compose logs -f --tail 100 backend  # solo backend
docker compose restart backend             # reiniciar un servicio
docker compose up -d --build backend       # reconstruir solo el backend
docker exec -it ra3-backend sh             # entrar al contenedor
docker exec -it ra3-db mysql -uroot -p     # entrar al MySQL
docker stats --no-stream                   # uso de CPU/RAM
```

Para recargar la configuracion de Nginx sin parar el contenedor:
```bash
docker exec ra3-proxy nginx -s reload
```

## Ciclo de actualizacion

1. Cambio la version en `docker-compose.yml` (por ejemplo `image: ra3/backend:1.1.0`).
2. `docker compose build backend`.
3. `docker compose up -d backend` (sustituye el contenedor sin afectar al resto).
4. Compruebo: `docker compose ps` + `curl localhost:8080/api/health`.
5. Si hay problemas, vuelvo a la version anterior cambiando la etiqueta.

## Seguridad aplicada

**Puertos**: solo el proxy publica `${HOST_HTTP_PORT}:8080`. La BD, el backend y el frontend no abren puertos al host. Se verifica con `docker compose ps`.

**Credenciales**: todas las contraseñas y usuarios pasan por variables de entorno definidas en `.env`. El `.env` esta en `.gitignore`, asi que no se sube al repositorio. Solo se sube `.env.example` con valores de ejemplo.

**Usuarios no root**:
- backend: usuario `spring` (uid 1001), creado en el Dockerfile con `adduser -S`.
- frontend y proxy: imagen `nginxinc/nginx-unprivileged` (uid 101).
- db: usuario `mysql` (el oficial de la imagen).

**no-new-privileges**: todos los servicios llevan `security_opt: no-new-privileges:true` para evitar que un proceso gane privilegios extra dentro del contenedor.

**Redes**: la red `backend-net` esta declarada como `internal: true`. La BD no tiene salida a Internet y solo el backend la alcanza.

**Versiones fijadas**: todas las imagenes llevan tag concreto:
- `mysql:8.0.39`
- `eclipse-temurin:17-jre-alpine`
- `nginxinc/nginx-unprivileged:1.27-alpine`
- `node:20-alpine`
- Imagenes propias: `ra3/backend:1.0.0`, `ra3/frontend:1.0.0`, `ra3/proxy:1.0.0`.

**Multi-stage builds**: las imagenes finales no llevan Maven, ni Node, ni codigo fuente.

**Validacion de input**: `@NotBlank`, `@Size(max=120)` y `@Size(max=1000)` en la entidad `Item`. Bean Validation rechaza entradas mal formadas con HTTP 400.

**Otros**: `client_max_body_size 5m` en el proxy, `limit_req` de 10 r/s en `/api/`, HikariCP con timeout de 10s. Cabeceras X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy.

**Permisos en la BD**: el usuario `ra3user` solo tiene SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES sobre `ra3app`. No es root.

Comprobaciones rapidas:
```bash
docker compose ps --format "table {{.Name}}\t{{.Ports}}"
docker exec ra3-backend id    # uid=1001 spring
docker network inspect ra3_backend-net --format '{{.Internal}}'   # true
```

## Mantenimiento

### Backups

`db_backup.sh` se puede lanzar manualmente o programado.

Linux (cron, todos los dias a las 03:00):
```
0 3 * * *  cd /ruta/RA3 && ./db_backup.sh >> /var/log/ra3_backup.log 2>&1
```

Windows (Programador de tareas), ejecutar con Git Bash:
```
"C:\Program Files\Git\bin\bash.exe" "C:\ruta\RA3\db_backup.sh"
```

El script aplica retencion de 7 dias automaticamente.

### Restore

```bash
docker compose stop backend
docker exec -i ra3-db mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ra3app < backups/ra3_backup_20260520_212745.sql
docker compose start backend
```

### Logs

Los logs JSON estan limitados por contenedor con `max-size: 10m` y `max-file: 3` en el docker-compose.yml. No hace falta rotacion manual.

### Volumenes

```bash
docker volume ls
docker system df
docker volume inspect ra3_db_data
```

Para limpiar espacio sin tocar datos:
```bash
docker image prune --filter "dangling=true"
docker system prune
```

Ojo: `docker volume prune` puede borrar `ra3_db_data` si el contenedor esta parado. Evitar.

## Escalabilidad

Aunque el despliegue es de un solo host, los puntos donde escalaria:

**Backend horizontal**: añadir `deploy.replicas: 3` a backend y quitar `container_name`. Nginx ya hace round-robin con los upstreams porque el DNS interno de Docker devuelve varias IPs.

**Vertical**: ajustar `deploy.resources.limits` segun lo que muestre `docker stats`. Limites actuales: 512M y 1 CPU para db y backend; el resto sin limite.

**Kubernetes**: `docker-compose.yml` se puede traducir con `kompose convert`. Equivalencias:
- `deploy.resources` -> `resources.limits/requests`
- `healthcheck` -> `livenessProbe` y `readinessProbe`
- `depends_on: service_healthy` -> init-container
- `networks.internal: true` -> NetworkPolicy

**Almacenamiento**: para multi-nodo, sustituir el volumen local por un volumen sobre NFS o un servicio gestionado tipo RDS.

## Resumen de pruebas

Las pruebas estan detalladas en `TESTING.md`. Resumen:

- GET / por navegador: carga la SPA, OK
- curl /api/health: HTTP 200 con `"status":"UP"`, OK
- curl /api/items: HTTP 200 con array de 3 items seed, OK
- POST con titulo vacio: HTTP 400 (validacion), OK
- DELETE id valido: HTTP 204, OK
- DELETE id inexistente: HTTP 404, OK
- frontend no resuelve la BD: getent hosts db exit=2, OK
- backend si resuelve la BD: exit=0, OK
- backend-net es internal=true, OK
- Solo proxy publica puerto: OK
- ./db_backup.sh genera .sql no vacio, OK
- Persistencia tras docker compose down/up: OK

## Incidencias frecuentes

**Backend no arranca con `Communications link failure`**: la BD no esta healthy todavia. `docker compose ps` y `docker compose logs db`. Si la BD esta OK pero el backend falla, comprobar `DB_PASSWORD` en `.env` (las credenciales solo se aplican al primer arranque; si cambias la password hay que `docker compose down -v` para regenerar el volumen).

**502/503 en el navegador**: el proxy no alcanza al upstream. `docker compose logs proxy` para ver `upstream prematurely closed`. Probar `docker exec ra3-proxy wget -qO- http://backend:8080/api/health`.

**Disco lleno por backups**: el script ya rota a 7 dias. Limpieza manual:
```bash
find backups/ -name 'ra3_backup_*.sql' -mtime +3 -delete
```
