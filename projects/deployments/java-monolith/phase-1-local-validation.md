# Phase 1: Local Validation & Environment Standardization

With the codebase modernized, the next crucial step in the DevSecOps pipeline is validating the application logic locally. Before writing a single line of Docker or Kubernetes configuration, the application must be proven to compile and execute predictably on bare metal. 

This phase documents the extraction of hardcoded configurations into a standardized environment variable schema, and the dual-database testing strategy utilizing both H2 and MySQL.

## Environment Variable Abstraction

The inherited codebase contained hardcoded database credentials and application settings directly within [`application.properties`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/src/main/resources/application.properties). This anti-pattern prevents portability across environments (Local, Docker, Kubernetes).

I refactored the application to rely entirely on environment variables, utilizing a [`.env`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/.env.example) pattern. The [`application.properties`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/src/main/resources/application.properties) was updated to read dynamically injected values:

```properties
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
server.port=${SERVER_PORT}
```

This ensures the exact same compiled `.jar` artifact can seamlessly switch between an in-memory test database and a production AWS RDS instance merely by swapping the environment variables at runtime.

### The Shell Truncation Bug

During local validation against MySQL, I encountered a silent database connection failure. The root cause was shell character parsing.

```env
# INCORRECT
SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/db?useSSL=false&serverTimezone=UTC

# CORRECT
SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/db?useSSL=false&serverTimezone=UTC"
```

!!! warning
    The `SPRING_DATASOURCE_URL` **must** be wrapped in double quotes. The `&` character in the query string is evaluated by bash as a background process operator. Without quotes, the shell truncates the URL at the first `&`, destroying the JDBC connection string before it ever reaches the JVM.

## Dual-Database Validation Strategy

To maximize developer velocity while maintaining production parity, I implemented and documented two distinct local validation paths: **H2 (In-Memory)** and **MySQL (Native)**. 

### Path A: Zero-Infrastructure Testing (H2)

For rapid iteration without requiring a running database daemon, the application is executed against the embedded H2 database (introduced in Phase 0).

1. **Configuration ([`.env`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/.env.example))**:
```env
SPRING_DATASOURCE_URL=jdbc:h2:mem:ibtisamIQ
SPRING_DATASOURCE_USERNAME=sa
SPRING_DATASOURCE_PASSWORD=password
```

2. **Configuration ([`application.properties`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/src/main/resources/application.properties))**:
The Hibernate dialect and JDBC driver must be explicitly swapped to `H2Dialect` and `org.h2.Driver`.
```properties
spring.datasource.driver-class-name=org.h2.Driver
spring.jpa.database-platform=org.hibernate.dialect.H2Dialect
spring.sql.init.mode=embedded
```

In this mode, executing `java -jar` provisions the schema in memory instantly, and data is wiped upon JVM termination.

### Path B: Production Parity Testing (MySQL)

Before committing to the CI pipeline, the application must be validated against the exact database engine it will encounter in production (MySQL 8.4).

1. **Configuration ([`.env`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/.env.example))**:
```env
SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/IbtisamIQbankappdb?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"
SPRING_DATASOURCE_USERNAME=real_user
SPRING_DATASOURCE_PASSWORD=real_password
```

2. **Configuration ([`application.properties`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/src/main/resources/application.properties))**:
```properties
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.jpa.database-platform=org.hibernate.dialect.MySQLDialect
```

## Compilation and Execution Execution

Once the environment variables are configured for either path, the validation sequence executes the Maven build lifecycle and boots the artifact:

```bash
# 1. Compile the artifact (skipping tests for raw execution validation)
./mvnw clean package -DskipTests

# 2. Source the environment and launch the JVM
set -a && source .env && set +a && java -jar target/bankapp-0.0.1-SNAPSHOT.jar
```

!!! tip
    **Why use `set -a`?** 
    By default, variables sourced from a [`.env`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/.env.example) file are kept local to the current shell. The `set -a` directive instructs bash to automatically export every defined variable into the environment of child processes (the JVM). `set +a` instantly disables this behavior to prevent bleeding subsequent shell variables.

Validating the application locally using this strict separation of concerns guarantees that any failures in the subsequent Docker or Kubernetes deployments are strictly infrastructure or networking issues, rather than application compilation faults.
