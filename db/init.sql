USE ra3app;

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES
  ON ra3app.* TO 'ra3user'@'%';
FLUSH PRIVILEGES;

CREATE TABLE IF NOT EXISTS items (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    title       VARCHAR(120) NOT NULL,
    description VARCHAR(1000) DEFAULT NULL,
    created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO items (title, description) VALUES
    ('Bienvenida',  'Si ves este item es que el frontend, el proxy, el backend y la BD se hablan correctamente.'),
    ('Multi-tier', 'Arquitectura React + Nginx + Spring Boot + MySQL orquestada con Docker Compose.'),
    ('Seguridad',  'Solo el proxy publica puerto. La red backend-net es interna.');
