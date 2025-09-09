# Highly-Available, Multi-Tenant PgBouncer on Kubernetes

This repository contains the configuration and deployment manifests for running a highly-available, multi-tenant PgBouncer instance on Kubernetes. This setup is designed to serve as a centralized connection pooler for various applications, reducing the number of direct connections to your PostgreSQL databases and improving overall performance and resource management.

 <!-- Replace with a real diagram URL -->
```mermaid
graph TD
    subgraph "Kubernetes Cluster"
        subgraph "Namespace: pgbouncer-shared"
            A[App 1] --> Svc;
            B[App 2] --> Svc;

            Svc(pgbouncer-svc<br/>ClusterIP Service) --> P1;
            Svc --> P2;
            Svc --> P3;

            P1[Pod: pgbouncer-1] -- Manages pool --> DB1[(PostgreSQL 1<br/>app1_prod_db)];
            P2[Pod: pgbouncer-2] -- Manages pool --> DB1;
            P3[Pod: pgbouncer-3] -- Manages pool --> DB2[(PostgreSQL 2<br/>app2_prod_db)];
            
            subgraph "PgBouncer Deployment (HA)"
                P1 & P2 & P3
            end

            P1 & P2 & P3 --> C((ConfigMap<br/>pgbouncer.ini));
            P1 & P2 & P3 --> Sec((Secret<br/>userlist.txt));
        end
    end
```
## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [PgBouncer Configuration (`pgbouncer.ini`)](#pgbouncer-configuration-pgbouncerini)
  - User Authentication (`userlist.txt`)
  - Database Mapping
- Deployment
  - 1. Create the Namespace
  - 2. Create the User Secret
  - 3. Create the ConfigMap
  - 4. Deploy PgBouncer
  - 5. Deploy the HPA
- Connecting from an Application
- Monitoring
- Contributing

## Features

*   **High Availability**: The deployment runs multiple PgBouncer replicas (`replicas: 3`) spread across different nodes using `podAntiAffinity` to prevent a single point of failure.
*   **Multi-Tenancy**: A single PgBouncer service can proxy connections for multiple, distinct databases, making it ideal for microservices architectures.
*   **Scalability**: Easily scale the number of PgBouncer replicas up or down by adjusting the `replicas` count in the `Deployment` manifest.
*   **Autoscaling**: A `HorizontalPodAutoscaler` (HPA) is included to automatically scale the number of PgBouncer pods based on CPU utilization.
*   **Health Checking**: `livenessProbe` and `readinessProbe` are configured to ensure traffic is only sent to healthy PgBouncer pods.

## Architecture

The setup consists of the following Kubernetes resources:

1.  **Deployment**: Manages the PgBouncer pods. It is configured for high availability with 3 replicas and anti-affinity rules.
2.  **ConfigMap**: Stores the main `pgbouncer.ini` configuration file. This allows for easy updates to settings without rebuilding the container image.
3.  **Secret**: Stores the `userlist.txt` file, which contains the usernames and hashed passwords for clients connecting to PgBouncer.
4.  **HorizontalPodAutoscaler (HPA)**: Automatically adjusts the number of PgBouncer replicas from 3 up to 100 based on CPU usage, ensuring performance under load.
4.  **Service** (Not included, but implied): A Kubernetes `Service` (e.g., `ClusterIP` or `LoadBalancer`) should be created to expose the PgBouncer deployment to other applications within the cluster. The service would target port `6432` on the pods with the label `app: pgbouncer`.

Applications connect to the PgBouncer service instead of directly to the PostgreSQL database. PgBouncer maintains a pool of connections to the upstream databases and assigns them to clients on a per-transaction basis (`pool_mode = transaction`).

## Prerequisites

*   A running Kubernetes cluster.
*   `kubectl` command-line tool configured to communicate with your cluster.
*   A container registry (like Harbor, as seen in the deployment) to host your PgBouncer container image.
*   One or more PostgreSQL databases accessible from the Kubernetes cluster.

## Configuration

### PgBouncer Configuration (`pgbouncer.ini`)

The main configuration is located in `deployment/config-ini.yaml`. Key settings include:

*   `listen_addr` & `listen_port`: Set to `*` and `6432` to listen on all interfaces inside the pod.
*   `auth_type`: `md5` is used for secure password authentication.
*   `auth_file`: Points to the user list file mounted from the Kubernetes `Secret`.
*   `admin_users` & `stats_users`: Defines users with administrative and monitoring privileges.
*   `pool_mode`: `transaction` is a common and effective pooling strategy.

### User Authentication (`userlist.txt`)

You must create a `userlist.txt` file that contains the users allowed to connect through PgBouncer. The format is:

```
"username" "md5_hashed_password"
```

**Example `userlist.txt`:**
```
"app1_user" "md5c7d4b5c5c3b1d2e3f4a5b6c7d8e9f0a1"
"app2_user" "md5a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
```

This file will be stored in a Kubernetes `Secret`.

### Database Mapping

The `[databases]` section in `pgbouncer.ini` is the core of the multi-tenant setup. It maps a "virtual" database name (which your application connects to) to a physical database connection string.

```ini
[databases]
app1_db = host=10.1.2.10 port=5432 dbname=app1_prod_db
app2_db = host=10.1.2.20 port=5432 dbname=app2_prod_db
```

*   An application wanting to connect to `app1_prod_db` will use the database name `app1_db` in its connection string when connecting to PgBouncer.
*   PgBouncer receives the connection and proxies it to the real database at `host=10.1.2.10`.

## Deployment

Follow these steps to deploy PgBouncer to your cluster.

### 1. Create the Namespace

All resources are deployed in the `pgbouncer-shared` namespace.

```bash
kubectl create namespace pgbouncer-shared
```

### 2. Create the User Secret

Create the `userlist.txt` file as described above, then create the secret from it.

```bash
kubectl create secret generic pgbouncer-userlist \
  --from-file=userlist.txt=./path/to/your/userlist.txt \
  --namespace pgbouncer-shared
```

### 3. Create the ConfigMap

Apply the `ConfigMap` manifest which contains the `pgbouncer.ini` configuration.

```bash
kubectl apply -f deployment/config-ini.yaml
```

### 4. Deploy the Service and Network Policy

Apply the `Service` and `NetworkPolicy` manifests.

```bash
kubectl apply -f deployment/service.yaml
kubectl apply -f deployment/netpol.yaml
```
### 4. Deploy PgBouncer

Apply the `Deployment` manifest.

```bash
kubectl apply -f deployment/pgbouncer-deployment.yaml
```

## Connecting from an Application

To connect from your application, you need to point it to the `pgbouncer-lb` service.

*   **From inside the cluster:** Use the Kubernetes DNS name.
    `postgres://app1_user:PASSWORD@pgbouncer-lb.pgbouncer-shared.svc.cluster.local:6432/app1_db`

*   **From outside the cluster:** Use the external IP address assigned to the `LoadBalancer` service. You can find this by running `kubectl get svc pgbouncer-lb -n pgbouncer-shared`.
    `postgres://app1_user:PASSWORD@<LOAD_BALANCER_EXTERNAL_IP>:6432/app1_db`

Note that the database name is `app1_db`, which is the virtual name defined in `pgbouncer.ini`.

## Monitoring

PgBouncer exposes statistics that can be collected by monitoring tools like Prometheus. The `stats_users` parameter in `pgbouncer.ini` defines a user (`pgbouncermetrics`) that can connect to the special `pgbouncer` database to run `SHOW` commands and gather metrics. You would typically deploy a Prometheus exporter alongside PgBouncer to scrape and expose these metrics.