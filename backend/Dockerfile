FROM maven:3.9.9-eclipse-temurin-17-alpine AS build
WORKDIR /workspace

COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests && mv target/*.jar target/app.jar


FROM eclipse-temurin:17-jre-alpine

RUN apk add --no-cache tzdata wget \
 && addgroup -S spring -g 1001 \
 && adduser  -S -G spring -u 1001 spring

WORKDIR /app
COPY --from=build /workspace/target/app.jar /app/app.jar
RUN chown -R spring:spring /app

USER spring:spring

EXPOSE 8080

ENV JAVA_OPTS=""

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
    CMD wget -q --tries=1 --spider http://127.0.0.1:8080/api/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
