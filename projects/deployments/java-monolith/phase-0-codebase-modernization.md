# Phase 0: Codebase Modernization

Before automating any CI/CD pipelines or provisioning infrastructure, the foundation—the application code itself—must be production-ready. The inherited Java monolith relied on outdated dependencies, hardcoded configurations, and lacked the necessary endpoints for container orchestration.

This phase documents the systematic audit and modernization of the codebase, focusing on dependency management, local development flexibility, and resolving complex edge-case bugs that surfaced during subsequent cloud deployments.

## [`pom.xml`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/pom.xml) Dependency Modernization

The [`pom.xml`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/pom.xml) was functional but built on deprecated dependencies. I executed a comprehensive upgrade to align the project with current industry standards:

| Artifact | Previous Version | Modernized Version | Rationale |
|---|---|---|---|
| **Spring Boot** | `3.3.3` | `3.4.4` | `3.3.x` reached end of OSS support. The upgrade provides critical security patches and native Java 21 optimizations. |
| **Java** | `17` | `21` | Java 21 is the current LTS release (supported until 2028), offering virtual threads and record patterns. |
| **MySQL Connector** | `8.0.33` (explicit) | BOM-Managed | The old artifact was deprecated. The new `groupId` is `com.mysql`, and omitting the version delegates control to the Spring Boot Bill of Materials (BOM), ensuring tested compatibility. |
| **JaCoCo** | `0.8.7` (duplicate) | `0.8.12` | Upgraded the coverage agent and removed an erroneous duplicate declaration in the `<dependencies>` block, placing it exclusively in `<plugins>`. |

### Orchestration Prerequisites

To prepare the application for Docker and Kubernetes, I injected two critical dependencies:

- **`spring-boot-starter-actuator`**: Exposes the `/actuator/health` endpoint. This is absolutely mandatory for Docker `HEALTHCHECK` instructions and Kubernetes liveness/readiness probes.
- **`spring-boot-starter-validation`**: Implements Jakarta Bean Validation, a strict requirement for production-grade REST input handling.

## Database Flexibility: Introducing H2

The original project tightly coupled development to a running MySQL server. I introduced the **H2 in-memory database** as a `runtime`-scoped dependency.

```xml
<dependency>
    <groupId>com.h2database</groupId>
    <artifactId>h2</artifactId>
    <scope>runtime</scope>
</dependency>
```

This structural change allows the application to boot locally in milliseconds without requiring Docker Compose or a native MySQL installation. Because H2 runs entirely within the JVM process and stores data in memory (`jdbc:h2:mem:`), it provides a zero-infrastructure testing path while retaining identical JPA semantics in the Java code.

## Application Code Refactoring: The ALB Edge Cases

During the AWS EC2 bare-metal deployment (Phase 4), the application was placed behind an Application Load Balancer (ALB). This surfaced two severe bugs in the application's configuration that caused infinite loops and health check failures. I resolved both by modifying the core application code.

### 1. The Health Check Redirect Bug

**The Symptom:** The AWS Auto Scaling Group continuously terminated and replaced EC2 instances because the ALB marked them as `unhealthy`.
**The Diagnosis:** Curling `/actuator/health` locally returned a `302 Redirect` instead of a `200 OK`.
**The Root Cause:** Spring Security's `.anyRequest().authenticated()` catch-all intercepted the unauthenticated ALB health checker and redirected it to the `/login` page.
**The Fix:** I modified [`SecurityConfig.java`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/src/main/java/com/ibtisam/bankapp/config/SecurityConfig.java) to explicitly permit the actuator endpoint before the catch-all:

```java
.authorizeHttpRequests(authz -> authz
        .requestMatchers("/register").permitAll()
        .requestMatchers("/actuator/health").permitAll()   // ← Added bypass
        .anyRequest().authenticated()
)
```

### 2. The HTTPS Login Redirect Loop

**The Symptom:** Users could access the login page over HTTPS, but submitting valid credentials resulted in an infinite redirect loop back to `/login`.
**The Diagnosis:** The ALB handled SSL termination (`443`), but forwarded traffic to the EC2 instances over HTTP (`8000`). 

**The Root Cause:** 

- Because Spring Boot received HTTP traffic, it generated `http://` redirects post-login. The browser, enforcing HTTPS, upgraded the request but lost the session context.
- The session cookie lacked the `Secure` and `SameSite` attributes, causing modern browsers to silently drop the session cookie over cross-context boundaries.

**The Fix:** I injected three critical properties into [`application.properties`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/src/main/resources/application.properties) to force Spring Boot to trust the ALB's `X-Forwarded-Proto: https` header and harden the session cookies:

```properties
# Trust X-Forwarded-Proto header from ALB
server.forward-headers-strategy=native

# Hardened session cookie requirements
server.servlet.session.cookie.secure=true
server.servlet.session.cookie.same-site=lax
```

These code-level modifications transformed a fragile local application into a robust, cloud-native artifact capable of surviving TLS termination and aggressive load balancer health checks.
