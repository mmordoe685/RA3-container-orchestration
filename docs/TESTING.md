# Pruebas y validacion

RA3 - Despliegue de Aplicaciones Web (2º DAW)

## 1. Pruebas funcionales

Compruebo que cada endpoint responde como debe.

```bash
# La SPA carga
curl -i http://localhost:8080/ | head -n 20

# Health del backend a traves del proxy
curl -i http://localhost:8080/api/health
# HTTP/1.1 200 OK
# {"status":"UP","service":"ra3-backend","timestamp":"..."}

# Listado de items (3 seed)
curl -s http://localhost:8080/api/items

# Crear item
curl -i -X POST http://localhost:8080/api/items \
     -H "Content-Type: application/json" \
     -d '{"title":"Prueba","description":"desde curl"}'
# HTTP/1.1 201 con el id nuevo

# Validacion - title vacio debe fallar
curl -i -X POST http://localhost:8080/api/items \
     -H "Content-Type: application/json" \
     -d '{"title":"","description":"x"}'
# HTTP/1.1 400

# Borrar
curl -i -X DELETE http://localhost:8080/api/items/4
# HTTP/1.1 204

# Borrar id inexistente
curl -i -X DELETE http://localhost:8080/api/items/999
# HTTP/1.1 404
```

Resultados:
- GET / -> 200, HTML con `<div id="root">`
- GET /api/health -> 200 con status UP
- GET /api/items -> 200, array JSON
- POST valido -> 201
- POST con title vacio -> 400 (Bean Validation)
- DELETE valido -> 204
- DELETE id inexistente -> 404

## 2. Comunicacion entre capas

Compruebo que el aislamiento de redes funciona.

```bash
# El backend resuelve la BD por DNS interno
docker exec ra3-backend sh -c 'getent hosts db'
# 172.x.x.x  db

# El frontend NO resuelve la BD (no esta en backend-net)
docker exec ra3-frontend sh -c 'getent hosts db; echo exit=$?'
# exit=2

# Solo el proxy publica puerto al host
docker compose ps --format "table {{.Name}}\t{{.Ports}}"
# ra3-proxy 0.0.0.0:8080->8080/tcp
# resto: solo puerto interno

# El proxy alcanza al backend
docker exec ra3-proxy wget -qO- http://backend:8080/api/health
```

Resumen:
- backend <-> db: OK (red backend-net)
- backend <-> proxy: OK (red app-net)
- frontend <-> proxy: OK (red app-net)
- frontend <-> db: DEBE fallar (no comparten red)
- host <-> db/backend/frontend directamente: DEBE fallar (no publican puerto)

## 3. Pruebas de carga

Con `ab` (Apache Benchmark) o con un bucle de curl.

```bash
# Endpoint estatico
ab -n 1000 -c 50 http://localhost:8080/

# Endpoint dinamico
ab -n 1000 -c 50 http://localhost:8080/api/items
```

Como referencia en mi maquina:
- GET / : > 800 r/s, < 25 ms por peticion, 0 fallos
- GET /api/items : > 300 r/s, < 80 ms por peticion, < 0.5% de fallos

### Rate limit del proxy

El proxy esta limitado a 10 r/s con burst 20. Una rafaga mayor debe rechazar:

```bash
for i in $(seq 1 200); do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/health
done | sort | uniq -c
# muchas 200 + algunas 503 (rechazadas por limit_req)
```

## 4. Validacion con logs

Los logs sirven para confirmar que el orden de arranque y los flujos funcionan.

```bash
# Confirmar el orden BD -> backend
docker compose logs db | head -n 30
docker compose logs backend | head -n 50
```

En el log del backend espero ver:
1. Banner de Spring Boot
2. `HikariPool-1 - Starting...`
3. `HikariPool-1 - Start completed.`
4. `Tomcat started on port 8080`

Si la BD no estuviera healthy, Compose retrasaria el arranque del backend, asi que nunca veo `Connection refused` en el primer arranque.

```bash
# Ver una peticion en el log del proxy
curl -s http://localhost:8080/api/items > /dev/null
docker compose logs --tail 5 proxy

# Estado de los healthchecks
docker inspect --format '{{json .State.Health}}' ra3-db
docker inspect --format '{{json .State.Health}}' ra3-backend
docker inspect --format '{{json .State.Health}}' ra3-frontend
docker inspect --format '{{json .State.Health}}' ra3-proxy
# Espero "Status":"healthy" en los 4
```

### Comprobaciones de seguridad

```bash
# Usuarios efectivos dentro de los contenedores
for s in db backend frontend proxy; do
  echo "=== $s ==="
  docker exec ra3-$s id
done
# db: uid=999(mysql)
# backend: uid=1001(spring)
# frontend: uid=101(nginx)
# proxy: uid=101(nginx)

# Confirmar que backend-net es interna
docker network inspect ra3_backend-net --format '{{.Internal}}'
# true
```

## 5. Pruebas del backup

```bash
./db_backup.sh
ls -lh backups/

# Comprobar que el dump tiene tabla y filas
grep -i 'CREATE TABLE\|INSERT INTO items' backups/ra3_backup_*.sql

# Restore destructivo de prueba
docker compose stop backend
docker exec -i ra3-db mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE ra3app; CREATE DATABASE ra3app CHARACTER SET utf8mb4;"
docker exec -i ra3-db mysql -uroot -p"$MYSQL_ROOT_PASSWORD" ra3app < backups/ra3_backup_*.sql
docker compose start backend
curl -s http://localhost:8080/api/items | grep -c '"id":'
# debe coincidir con lo respaldado
```

## 6. Checklist antes de la entrega

- [ ] `docker compose up -d --build` arranca sin errores
- [ ] `docker compose ps` muestra los 4 servicios healthy
- [ ] La SPA carga en http://localhost:8080 y muestra los 3 items seed
- [ ] Se puede crear, listar y borrar items desde el formulario
- [ ] curl a /api/* funciona (health, items)
- [ ] `./db_backup.sh` genera un .sql no vacio en `./backups/`
- [ ] `docker compose down && docker compose up -d` mantiene los datos
- [ ] Logs sin stack traces en arranque limpio
