# --- Build stage ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
# Warm the dependency cache in its own layer so code-only changes don't
# re-download the internet on every Jenkins build.
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B clean package -DskipTests

# --- Runtime stage ---
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

# Run as a non-root user inside the container.
RUN useradd --system --create-home --shell /usr/sbin/nologin ekart
USER ekart

COPY --from=build /build/target/ekart.jar /app/ekart.jar

EXPOSE 8070

ENTRYPOINT ["java", "-jar", "/app/ekart.jar"]
