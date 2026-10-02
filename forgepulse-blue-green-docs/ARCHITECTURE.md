# ForgePulse Blue-Green Architecture

## 1. Purpose

This document explains the architecture used by the ForgePulse Blue-Green Deployment project.

The implementation is intentionally local so that the deployment strategy can be understood without AWS infrastructure.

---

## 2. High-Level Architecture

```text
                         User Browser
                              |
                              v
                       localhost:80
                              |
                              v
                    +-------------------+
                    |       NGINX       |
                    | Reverse Proxy     |
                    | Traffic Switching |
                    +---------+---------+
                              |
                +-------------+-------------+
                |                           |
                v                           v
        +---------------+           +---------------+
        | 🔵 BLUE       |           | 🟢 GREEN      |
        | Version 1.0   |           | Version 2.0   |
        | Port 8081     |           | Port 8082     |
        +---------------+           +---------------+
                |                           |
                +-------------+-------------+
                              |
                           Docker
```

---

## 3. Blue Environment

Blue is the currently active production environment.

```text
Container:
forgepulse-blue

Host Port:
8081

Container Port:
5000

Example:
http://localhost:8081
```

Blue can contain the currently stable application release.

---

## 4. Green Environment

Green contains the new application release.

```text
Container:
forgepulse-green

Host Port:
8082

Container Port:
5000

Example:
http://localhost:8082
```

Green is validated before production traffic is sent to it.

---

## 5. Nginx Traffic Control

Nginx acts as the traffic switch.

Blue active:

```nginx
upstream forgepulse_backend {
    server 127.0.0.1:8081;
}
```

Green active:

```nginx
upstream forgepulse_backend {
    server 127.0.0.1:8082;
}
```

The application containers can remain running while Nginx changes the active backend.

---

## 6. Deployment Flow

```text
Version 1
   |
   v
BLUE
   |
   | Production traffic
   v
Users


New Version 2
   |
   v
GREEN
   |
   | Health checks
   v
Validation
   |
   v
Traffic switch
   |
   v
GREEN becomes production
```

---

## 7. Rollback Flow

```text
GREEN v2
   |
   | Application problem
   v
Rollback
   |
   v
Nginx switches backend
   |
   v
BLUE v1
   |
   v
Users restored to previous release
```

---

## 8. Why This Architecture Works

The main principle is:

> Deploy first, validate second, switch traffic last.

The new version does not immediately replace the active production version.

This separates deployment from production exposure.

---

## 9. Ports

| Component | Port |
|---|---:|
| Nginx | 80 |
| Blue | 8081 |
| Green | 8082 |
| Flask inside container | 5000 |

---

## 10. Health Check

The application exposes:

```text
GET /health
```

Example:

```json
{
  "status": "healthy",
  "version": "2.0.0",
  "environment": "GREEN"
}
```

The deployment should continue only after the health endpoint returns successfully.

---

## 11. Failure Scenarios

### Green fails before promotion

```text
Blue = Production
Green = Failed

Result:
No production traffic is changed.
```

### Green fails after promotion

```text
Green = Production
Blue = Standby

Result:
Switch Nginx back to Blue.
```

### Nginx configuration error

Always validate:

```bash
sudo nginx -t
```

before reloading.

---

## 12. Production Traffic Model

Only one environment should normally be considered active production traffic.

```text
             Nginx
               |
       +-------+-------+
       |               |
      BLUE            GREEN
       |               |
      ACTIVE          STANDBY
```

After promotion:

```text
             Nginx
               |
       +-------+-------+
       |               |
      BLUE            GREEN
       |               |
    STANDBY           ACTIVE
```

---

## 13. CI/CD Extension

Jenkins can automate:

```text
Git Push
   |
   v
Jenkins
   |
   v
Test
   |
   v
Build Docker Image
   |
   v
Deploy Green
   |
   v
Health Check
   |
   v
Switch Traffic
   |
   v
Production
```

---

## 14. Future Cloud Equivalent

The same concept can later be implemented using cloud infrastructure.

For example:

```text
Local:
Nginx → Blue / Green Docker containers

Cloud:
Load Balancer → Blue / Green application environments
```

The infrastructure changes, but the deployment principle remains the same.
