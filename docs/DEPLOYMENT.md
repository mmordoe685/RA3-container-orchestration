# Manual de despliegue

RA3 - Despliegue de Aplicaciones Web (2º DAW)

## Arquitectura

La aplicacion se reparte en cuatro contenedores:

- **proxy**: Nginx que actua como reverse proxy. Es el unico que publica un puerto al host (8080).
- **frontend**: React + Vite, compilado a estatico y servido por Nginx.
- **backend**: Spring Boot 3 con Java 17, expone una API REST en /api.
- **db**: MySQL 8 con volumen persistente.

El proxy reenvia las peticiones que empiezan por /api al backend, y el resto al frontend.

El backend solo se conecta a la BD por una red interna (backend-net) que no tiene salida a Internet. La red app-net conecta proxy con frontend y backend.

```
navegador -> :8080 proxy -> frontend (estatico)
                        -> backend  -> db (red interna)
```

## Servicios

### proxy
Imagen `nginxinc/nginx-unprivileged:1.27-alpine`. Corre como usuario nginx (uid 101). Su configuracion esta en `proxy/nginx.conf`.

### frontend
Compila la app React con Vite en una imagen de Node y copia solo el resultado (`dist/`) a una imagen de Nginx unprivileged. No queda Node ni node_modules en la imagen final.

### backend
Spring Boot empaqueta un Tomcat embebido. Spring Data JPA + Hibernate hablan con MySQL a traves de HikariCP. La validacion se hace con Jakarta Bean Validation.

Componentes:
- Tomcat embebido en :8080
- Spring MVC para las rutas REST (`ItemController`, `HealthController`)
- Spring Data JPA + Hibernate
- HikariCP (pool de conexiones, 10 max)
- Driver MySQL Connector/J

Ficheros principales:
- `backend/pom.xml`: dependencias Maven
- `backend/src/main/resources/application.properties`: configuracion del datasource, JPA y puerto
- `backend/Dockerfile`: multi-stage build

Ajustes que he aplicado:
- `server.address=0.0.0.0` para que escuche tambien desde el proxy
- `server.shutdown=graceful` para dar tiempo a cerrar peticiones
- `spring.jpa.open-in-view=false` para no mantener la sesion JPA abierta toda la peticion
- HikariCP a 10 conexiones (encaja con los 512M de RAM del contenedor)

### db
MySQL 8. Tiene un init.sql en `db/` que se ejecuta la primera vez para crear la tabla `items` y meter 3 filas de prueba.

## Proxy inverso

El `proxy/nginx.conf` define dos `upstream` (backend:8080 y frontend:8080) y un `server` que escucha en 8080. La ruta `/api/` va al backend y `/` al frontend. Tambien manda cabeceras de seguridad (`X-Content-Type-Options`, `X-Frame-Options`, etc.) y limita peticiones a 10 r/s con `limit_req_zone`.

Cabeceras que reenvio al backend para que vea la IP original:
- `X-Real-IP`
- `X-Forwarded-For`
- `X-Forwarded-Proto`

Tiene un endpoint propio `/healthz` para el healthcheck.

## Multi-stage builds

Hago multi-stage en backend y frontend para que la imagen final no lleve el SDK de compilacion.

**Backend**: la primera fase usa `maven:3.9.9-eclipse-temurin-17-alpine` para compilar el JAR. La segunda solo coge el JAR y lo mete en `eclipse-temurin:17-jre-alpine`. Asi la imagen final no tiene Maven ni el codigo fuente, solo el JAR. Pasa de unos 500 MB a unos 180 MB.

**Frontend**: la primera fase es `node:20-alpine`, instala dependencias y compila con Vite. La segunda solo copia el resultado `dist/` a `nginxinc/nginx-unprivileged:1.27-alpine`. La imagen final no tiene Node ni node_modules, solo HTML/CSS/JS minificado. Pasa de unos 350 MB a unos 25 MB.

Ventajas:
- Menos superficie de ataque (no hay compiladores ni gestores de paquetes en runtime)
- Imagenes mucho mas pequeñas, descargas mas rapidas
- El codigo fuente no se distribuye

## Healthchecks

Los healthchecks evitan que el backend arranque antes de que MySQL este listo, lo que causaba `Communications link failure`.

Configuracion:

```yaml
db:
  healthcheck:
    test: mysqladmin ping ...
    interval: 10s, start_period: 30s, retries: 10

backend:
  depends_on:
    db:
      condition: service_healthy
```

Asi Compose espera a que `db` pase a estado healthy (varios ping OK) antes de arrancar el backend. Una vez sano, el backend abre el pool HikariCP sin reintentos y sin errores en los logs.

Todos los servicios tienen healthcheck propio para que `docker compose ps` muestre el estado real.

## Pasos para desplegar

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps   # verificar 4 healthy
```

Abrir http://localhost:8080 en el navegador.

Parar conservando datos:
```bash
docker compose stop
```

Parar y borrar contenedores (mantiene volumen):
```bash
docker compose down
```

Borrado total con datos:
```bash
docker compose down -v
```

Actualizar tras cambios en el codigo:
```bash
docker compose up -d --build
```

## Ficheros de configuracion

- `docker-compose.yml`: orquestacion, redes, volumenes, limites de recursos
- `.env` / `.env.example`: credenciales y puerto del host
- `backend/Dockerfile`, `frontend/Dockerfile`, `proxy/Dockerfile`
- `backend/src/main/resources/application.properties`: Spring Boot
- `frontend/nginx.conf`, `proxy/nginx.conf`
- `db/init.sql`: schema y seed
- `db_backup.sh`: script de backup
