# Phase 2: Docker Containerization

Following successful local bare-metal validation, the next milestone in the DevSecOps journey is containerizing the application. This ensures the artifact runs identically across all downstream environments (AWS EC2, ECS, and Kubernetes).

## The Multi-Stage [Dockerfile](https://github.com/ibtisam-iq/java-monolith-app/blob/main/Dockerfile)

A poorly optimized Java Docker image can easily exceed 500MB, carrying unnecessary build tools (`maven`) and source code into production. I implemented a strict **multi-stage build** to optimize the image size (down to ~165MB) and reduce the attack surface.

### Stage 1: The Builder (Layer Optimization)
The builder stage uses `maven:3.9.9-eclipse-temurin-21-alpine`. 

The most critical optimization in this stage is the layer ordering to maximize Docker build cache efficiency:

```dockerfile
COPY pom.xml .
RUN mvn dependency:go-offline -B --no-transfer-progress
COPY src ./src
RUN mvn clean package -DskipTests -B --no-transfer-progress
```

By copying `pom.xml` and running `dependency:go-offline` *before* copying the `src/` directory, all Maven dependencies are downloaded and cached permanently. When Java source code changes, only the `src` copy and `package` layers re-run, dropping build times from 3+ minutes to ~15 seconds.

### Stage 2: The Runtime (Security and Optimization)
The runtime stage discards the JDK and all source code, starting fresh from the minimal `eclipse-temurin:21-jre-alpine` image. 

#### Non-Root Execution
To comply with CIS benchmarks and pass Trivy security scans (and Kubernetes PodSecurityAdmission restricted policies), the image creates and runs as a minimal system user:

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /usr/src/app/target/*.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
```
!!! warning
    The order of operations here is absolute. The `chown` command must execute while the user is still `root`, and only after that can the context switch to `USER appuser`.

#### Container-Aware JVM Flags
The `ENTRYPOINT` is defined in exec form (`["java", ...]`) so the JVM operates as PID 1 and gracefully handles `SIGTERM`.

Critically, the JVM must be configured to respect Linux cgroups instead of host memory:
```dockerfile
ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
```

- `-XX:+UseContainerSupport`: Forces the JVM to read container memory limits rather than the host VM's total RAM, preventing kernel `OOMKilled` terminations in Kubernetes.
- `-XX:MaxRAMPercentage=75.0`: Allocates 75% of the container limit to the heap, reserving 25% for the OS, metaspace, and native memory.
- `-Djava.security.egd=file:/dev/./urandom`: Prevents startup stalls caused by Java's `SecureRandom` blocking on a depleted entropy pool (`/dev/random`).

## Docker Compose Orchestration

To validate the containerized architecture locally before pushing it to CI pipelines, I authored a [`compose.yml`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/compose.yml) file orchestrating the Spring Boot application and a MySQL 8.4 database.

### Intelligent Service Dependency

A common race condition occurs when the application container boots faster than the database container, causing Spring Boot to crash immediately upon connection failure. To solve this, I implemented Docker's `depends_on` with `condition: service_healthy`:

1. The `db` container starts and runs `mysqladmin ping -h localhost`.
2. The `web` container halts initialization until the `db` health check passes.
3. Spring Boot connects to MySQL using the internal Docker DNS service name (`db`) instead of `localhost`.

### Handling Spring Boot Cold Starts

I meticulously tuned the `web` container's internal health check. Spring Boot with JPA + MySQL connection pool initialization consistently takes 45-60 seconds on a cold start.

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8000/actuator/health || exit 1
```
Setting `--start-period=60s` prevents Docker from prematurely marking the container as unhealthy while Hibernate is still initializing the database schema.
