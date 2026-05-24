# Development Containers with Distrobox, Podman, and PostgreSQL

This setup provides isolated development containers for different technology stacks using **Distrobox** and **Podman**.

It also includes a shared PostgreSQL service running in Podman, connected through a custom Podman network called `dev-net`.

## Project Directory Structure

Recommended directory structure:

```text
~/Documents/Code/
.
├── astro-dev
├── java-dev
├── js-ts-dev
├── python-dev
├── react-django-dev
├── react-express-dev
├── react-springboot-dev
└── services
    └── postgres/
````

The development containers are created with their own home directories inside:

```text
~/Documents/Code/<container-name>
```

For example:

```text
~/Documents/Code/react-springboot-dev
```

The PostgreSQL service can be managed separately from:

```text
~/Documents/Code/services/postgres
```

---

## 1. Create the Podman Network

Before creating the development containers or PostgreSQL service, create a shared Podman network:

```bash
podman network create dev-net
```

Verify that the network was created:

```bash
podman network ls
```

You should see `dev-net` in the list.

---

## 2. Create the PostgreSQL Service

Create and start a PostgreSQL container connected to the `dev-net` network:

```bash
podman run -d \
  --name postgres-dev \
  --network dev-net \
  -e POSTGRES_USER=dev \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=postgres \
  -v postgres-dev-data:/var/lib/postgresql/data \
  -p 5432:5432 \
  docker.io/library/postgres:16
```

This command creates a PostgreSQL container with:

| Option                                          | Description                                           |
| ----------------------------------------------- | ----------------------------------------------------- |
| `--name postgres-dev`                           | Container name                                        |
| `--network dev-net`                             | Connects PostgreSQL to the shared development network |
| `POSTGRES_USER=dev`                             | Database username                                     |
| `POSTGRES_PASSWORD=secret`                      | Database password                                     |
| `POSTGRES_DB=postgres`                          | Default database                                      |
| `-v postgres-dev-data:/var/lib/postgresql/data` | Persistent PostgreSQL data volume                     |
| `-p 5432:5432`                                  | Exposes PostgreSQL on the host machine                |

Check that the PostgreSQL container is running:

```bash
podman ps
```

---

## 3. Connect to PostgreSQL from the Host

You can access the PostgreSQL service directly using:

```bash
podman exec -it postgres-dev psql -U dev -d postgres
```

Inside `psql`, you can list databases with:

```sql
\l
```

Create a new database:

```sql
CREATE DATABASE my_project_db;
```

Connect to the new database:

```sql
\c my_project_db
```

List tables:

```sql
\dt
```

Exit `psql`:

```sql
\q
```

---

## 4. Create a Development Container

The script creates development containers using Distrobox.

Available stacks:

```text
astro
js-ts
react-django
react-express
react-springboot
java
all
```

Make the script executable:

```bash
chmod +x create-dev-container.sh
```

Create a React + Spring Boot development container:

```bash
./create-dev-container.sh react-springboot
```

Create a React + Django development container:

```bash
./create-dev-container.sh react-django
```

Create a React + Express development container:

```bash
./create-dev-container.sh react-express
```

Create all containers:

```bash
./create-dev-container.sh all
```

The backend-oriented containers are attached to the `dev-net` network so they can communicate with the PostgreSQL container.

These containers include:

| Stack              | Main Tools                                                      |
| ------------------ | --------------------------------------------------------------- |
| `react-django`     | Node.js, pnpm, Python, pip, virtualenv, PostgreSQL client tools |
| `react-express`    | Node.js, pnpm                                                   |
| `react-springboot` | Node.js, pnpm, Java, Maven, Gradle, Spring Boot CLI             |
| `java`             | Java, Maven, Gradle                                             |
| `astro`            | Node.js, pnpm                                                   |
| `js-ts`            | Node.js, pnpm                                                   |

---

## 5. Enter a Development Container

To enter a container manually:

```bash
distrobox enter react-springboot-dev
```

Or:

```bash
distrobox enter react-django-dev
```

Or:

```bash
distrobox enter react-express-dev
```

---

## 6. Using PostgreSQL from a Development Container

When connecting from another Podman container on the same network, do not use `localhost`.

Use the PostgreSQL container name as the host:

```text
postgres-dev
```

Connection values:

```env
DB_HOST=postgres-dev
DB_PORT=5432
DB_NAME=postgres
DB_USER=dev
DB_PASSWORD=secret
```

The reason is that `localhost` inside a development container refers to the development container itself, not the PostgreSQL container.

---

## 7. Example: Spring Boot Configuration

Inside a Spring Boot project, configure PostgreSQL in `application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://postgres-dev:5432/postgres
spring.datasource.username=dev
spring.datasource.password=secret

spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true
```

Or using `application.yml`:

```yaml
spring:
  datasource:
    url: jdbc:postgresql://postgres-dev:5432/postgres
    username: dev
    password: secret

  jpa:
    hibernate:
      ddl-auto: update
    show-sql: true
    properties:
      hibernate:
        format_sql: true
```

---

## 8. Example: Django Configuration

Install the PostgreSQL driver inside your Django virtual environment:

```bash
pip install psycopg[binary]
```

Example `settings.py` database configuration:

```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "postgres",
        "USER": "dev",
        "PASSWORD": "secret",
        "HOST": "postgres-dev",
        "PORT": "5432",
    }
}
```

Run migrations:

```bash
python manage.py migrate
```

---

## 9. Example: Express Configuration

Install the PostgreSQL client:

```bash
pnpm add pg
```

Example `.env` file:

```env
DATABASE_URL=postgresql://dev:secret@postgres-dev:5432/postgres
```

Example connection using `pg`:

```js
import pg from "pg";

const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const result = await pool.query("SELECT NOW()");
console.log(result.rows);
```

---

## 10. Verify Network Connectivity

Check that PostgreSQL is connected to `dev-net`:

```bash
podman inspect postgres-dev | grep -A 20 Networks
```

Check that the development container is connected to `dev-net`:

```bash
podman inspect react-springboot-dev | grep -A 20 Networks
```

You can also test connectivity from inside the development container:

```bash
distrobox enter react-springboot-dev
```

Then:

```bash
ping postgres-dev
```

If `ping` is not installed, test using PostgreSQL tools or your application connection instead.

---

## 11. Common Commands

Start PostgreSQL:

```bash
podman start postgres-dev
```

Stop PostgreSQL:

```bash
podman stop postgres-dev
```

Restart PostgreSQL:

```bash
podman restart postgres-dev
```

View PostgreSQL logs:

```bash
podman logs postgres-dev
```

Follow PostgreSQL logs:

```bash
podman logs -f postgres-dev
```

Enter PostgreSQL with `psql`:

```bash
podman exec -it postgres-dev psql -U dev -d postgres
```

Remove the PostgreSQL container:

```bash
podman rm -f postgres-dev
```

Remove the PostgreSQL volume:

```bash
podman volume rm postgres-dev-data
```

Warning: removing the volume deletes the database data.

---

## 12. Recommended Workflow

Start the PostgreSQL service:

```bash
podman start postgres-dev
```

Create or enter your development container:

```bash
./create-dev-container.sh react-springboot
```

Or enter an existing one:

```bash
distrobox enter react-springboot-dev
```

Create your project inside the container home directory:

```bash
cd ~
```

For example:

```bash
mkdir my-springboot-app
cd my-springboot-app
```

Configure the project to connect to PostgreSQL using:

```text
postgres-dev:5432
```

Run your development server from inside the container.

---

## 13. Important Notes

Use `postgres-dev` as the database hostname when connecting from a development container.

Use `localhost` only when connecting from the host machine.

For example:

From the host:

```text
localhost:5432
```

From a development container:

```text
postgres-dev:5432
```

The PostgreSQL data is stored in the Podman volume:

```text
postgres-dev-data
```

This allows the database data to persist even if the PostgreSQL container is stopped or recreated.
