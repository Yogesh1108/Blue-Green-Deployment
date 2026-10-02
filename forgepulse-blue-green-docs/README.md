# ForgePulse Blue-Green Deployment

A local DevOps project demonstrating **Blue-Green Deployment** for ForgePulse, a simple customer support analytics platform.

The project uses **Docker + Nginx + a simple Flask application** to demonstrate near-zero-downtime application releases, pre-production validation, traffic switching, and fast rollback — without using AWS services.

---

## Project Objective

ForgePulse needs a deployment process that allows new application versions to be released with minimal downtime and provides a quick way to return to the previous version if the new release has problems.

This project implements:

- Two identical application environments
- Blue production environment
- Green release environment
- Nginx traffic switching
- Docker-based application deployment
- Application health checks
- Version validation before production traffic is switched
- Rollback to the previous version
- A simple real-time website that visibly shows the active environment

---

## Architecture

```text
                         Browser
                            |
                            | http://localhost
                            v
                    +----------------+
                    |     NGINX      |
                    | Traffic Switch |
                    |      :80       |
                    +-------+--------+
                            |
                  +---------+---------+
                  |                   |
                  v                   v
           BLUE :8081          GREEN :8082
            v1.0.0                v2.0.0
                  |                   |
                  +---------+---------+
                            |
                          Docker
```

Only one environment receives production traffic at a time.

Example:

```text
Before deployment:

Users ---> Nginx ---> BLUE v1.0.0
                     GREEN v2.0.0
                     No production traffic


After successful deployment:

Users ---> Nginx ---> GREEN v2.0.0
                     BLUE v1.0.0
                     Standby
```

If the new version fails:

```text
Users ---> Nginx ---> BLUE v1.0.0

GREEN v2.0.0
Problem detected
```

---

## Technology Stack

| Technology | Purpose |
|---|---|
| Ubuntu Linux | Local deployment environment |
| Python | Simple application |
| Flask | Web application framework |
| Docker | Application containerization |
| Nginx | Reverse proxy and traffic switch |
| Git/GitHub | Source control |
| Jenkins | Optional CI/CD automation |
| curl | Health and API testing |

No AWS services are required.

---

# 1. Prerequisites

Check the local system:

```bash
lsb_release -a
docker --version
nginx -v
git --version
```

Optional Jenkins:

```bash
java -version
jenkins --version
```

---

# 2. Create the Project

```bash
mkdir -p ~/Desktop/DevOPs-Projects/forgepulse-blue-green
cd ~/Desktop/DevOPs-Projects/forgepulse-blue-green
```

Create directories:

```bash
mkdir -p app nginx scripts tests
```

Expected structure:

```text
forgepulse-blue-green/
├── app/
├── nginx/
├── scripts/
└── tests/
```

---

# 3. Create the Flask Application

Move into the application directory:

```bash
cd ~/Desktop/DevOPs-Projects/forgepulse-blue-green/app
```

Create the application:

```bash
nano app.py
```

The application should expose:

```text
GET /
GET /health
```

The `/` page displays:

- ForgePulse Analytics
- Active environment
- Application version
- Health status

The `/health` endpoint returns JSON similar to:

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "environment": "BLUE"
}
```

Create:

```bash
nano requirements.txt
```

Add:

```text
Flask==3.0.3
```

---

# 4. Create the Dockerfile

Inside `app/`:

```bash
nano Dockerfile
```

Use:

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

---

# 5. Build Version 1

From the `app` directory:

```bash
docker build -t forgepulse:1.0 .
```

Verify:

```bash
docker images
```

---

# 6. Start the Blue Environment

Run:

```bash
docker run -d \
  --name forgepulse-blue \
  -p 8081:5000 \
  forgepulse:1.0
```

Verify:

```bash
docker ps
```

Test:

```bash
curl http://localhost:8081/health
```

Expected:

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "environment": "BLUE"
}
```

Open:

```text
http://localhost:8081
```

You should see the Blue environment.

---

# 7. Start the Green Environment

Initially Green can run the same application image:

```bash
docker run -d \
  --name forgepulse-green \
  -p 8082:5000 \
  forgepulse:1.0
```

Verify:

```bash
docker ps
```

Test:

```bash
curl http://localhost:8082/health
```

At this point:

```text
BLUE  -> localhost:8081
GREEN -> localhost:8082
```

---

# 8. Install Nginx

Check:

```bash
nginx -v
```

If necessary:

```bash
sudo apt update
sudo apt install nginx -y
```

Enable and start:

```bash
sudo systemctl enable --now nginx
```

Verify:

```bash
sudo systemctl status nginx
```

---

# 9. Configure Nginx

Create:

```bash
sudo nano /etc/nginx/sites-available/forgepulse
```

For Blue to be active:

```nginx
upstream forgepulse_backend {
    server 127.0.0.1:8081;
}

server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://forgepulse_backend;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Remove the default site:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
```

Enable ForgePulse:

```bash
sudo ln -s /etc/nginx/sites-available/forgepulse \
/etc/nginx/sites-enabled/forgepulse
```

Validate:

```bash
sudo nginx -t
```

Reload:

```bash
sudo systemctl reload nginx
```

Open:

```text
http://localhost
```

Production traffic should now go to Blue.

---

# 10. Create Version 2

Edit the application:

```bash
cd ~/Desktop/DevOPs-Projects/forgepulse-blue-green/app
nano app.py
```

Change:

```python
VERSION = "1.0.0"
ENVIRONMENT = "BLUE"
```

to:

```python
VERSION = "2.0.0"
ENVIRONMENT = "GREEN"
```

You can also change the visible website content to make Version 2 obvious.

---

# 11. Build Version 2

```bash
docker build -t forgepulse:2.0 .
```

Verify:

```bash
docker images
```

---

# 12. Deploy Version 2 to Green

Remove the old Green container:

```bash
docker rm -f forgepulse-green
```

Start the new Green release:

```bash
docker run -d \
  --name forgepulse-green \
  -p 8082:5000 \
  forgepulse:2.0
```

Verify:

```bash
docker ps
```

Important:

**Do not switch Nginx yet.**

Users should still be using Blue.

---

# 13. Validate Green

Test the health endpoint:

```bash
curl http://localhost:8082/health
```

Expected:

```json
{
  "status": "healthy",
  "version": "2.0.0",
  "environment": "GREEN"
}
```

Test HTTP response:

```bash
curl -I http://localhost:8082
```

Expected:

```text
HTTP/1.1 200 OK
```

Run multiple checks:

```bash
for i in {1..5}; do
    curl -s http://localhost:8082/health
    echo
done
```

Only continue if Green passes validation.

---

# 14. Switch Production Traffic to Green

Edit:

```bash
sudo nano /etc/nginx/sites-available/forgepulse
```

Change:

```nginx
server 127.0.0.1:8081;
```

to:

```nginx
server 127.0.0.1:8082;
```

Validate:

```bash
sudo nginx -t
```

Reload:

```bash
sudo systemctl reload nginx
```

Open:

```text
http://localhost
```

The website should now show:

```text
GREEN ENVIRONMENT
Version 2.0.0
```

Traffic has been switched from Blue to Green.

---

# 15. Understand the Traffic Switch

Before:

```text
Browser
   |
   v
 Nginx
   |
   v
BLUE :8081
v1.0.0
```

After:

```text
Browser
   |
   v
 Nginx
   |
   v
GREEN :8082
v2.0.0
```

The application containers do not need to be recreated during the traffic switch.

Only the Nginx upstream target changes.

---

# 16. Perform a Rollback

Simulate a Green failure:

```bash
docker stop forgepulse-green
```

Check:

```bash
curl http://localhost:8082/health
```

Green is now unavailable.

Switch Nginx back to Blue:

```bash
sudo nano /etc/nginx/sites-available/forgepulse
```

Change:

```nginx
server 127.0.0.1:8082;
```

to:

```nginx
server 127.0.0.1:8081;
```

Validate:

```bash
sudo nginx -t
```

Reload:

```bash
sudo systemctl reload nginx
```

Open:

```text
http://localhost
```

The website should show:

```text
BLUE ENVIRONMENT
Version 1.0.0
```

This demonstrates the rollback mechanism.

---

# 17. Deployment Lifecycle

```text
Developer
    |
    v
GitHub
    |
    v
Build Version 2
    |
    v
Deploy to GREEN
    |
    v
Health Checks
    |
    +-------- FAIL --------> Stop Deployment
    |
   PASS
    |
    v
Switch Nginx
    |
    v
GREEN becomes Production
    |
    v
Monitor
    |
    +-------- Problem -----> Rollback to BLUE
    |
    v
Continue with GREEN
```

---

# 18. Useful Docker Commands

List containers:

```bash
docker ps
```

List all containers:

```bash
docker ps -a
```

View Blue logs:

```bash
docker logs forgepulse-blue
```

View Green logs:

```bash
docker logs forgepulse-green
```

Follow logs:

```bash
docker logs -f forgepulse-green
```

Stop Blue:

```bash
docker stop forgepulse-blue
```

Stop Green:

```bash
docker stop forgepulse-green
```

Remove a container:

```bash
docker rm forgepulse-blue
```

List images:

```bash
docker images
```

---

# 19. Useful Nginx Commands

Test configuration:

```bash
sudo nginx -t
```

Reload:

```bash
sudo systemctl reload nginx
```

Restart:

```bash
sudo systemctl restart nginx
```

Status:

```bash
sudo systemctl status nginx
```

View access logs:

```bash
sudo tail -f /var/log/nginx/access.log
```

View error logs:

```bash
sudo tail -f /var/log/nginx/error.log
```

---

# 20. Optional Jenkins Automation

After the manual deployment works, Jenkins can automate:

```text
Checkout
   ↓
Test
   ↓
Build Docker Image
   ↓
Deploy Green
   ↓
Health Check
   ↓
Switch Traffic
   ↓
Monitor
```

A Jenkins pipeline can eventually execute:

```text
docker build
docker run
curl /health
nginx configuration update
nginx -t
systemctl reload nginx
```

The recommended learning order is:

```text
Manual Blue-Green
        ↓
Docker
        ↓
Nginx
        ↓
Health Checks
        ↓
Rollback
        ↓
Jenkins Automation
        ↓
Kubernetes
        ↓
Cloud Blue-Green
```

---

# 21. Verification Checklist

Use this checklist before considering the project complete.

- [ ] Docker installed
- [ ] Flask application created
- [ ] Dockerfile created
- [ ] Version 1 image built
- [ ] Blue container running
- [ ] Green container running
- [ ] Nginx installed
- [ ] Nginx reverse proxy configured
- [ ] Browser can access ForgePulse
- [ ] Blue is initially receiving traffic
- [ ] Version 2 image created
- [ ] Version 2 deployed to Green
- [ ] Green health check passes
- [ ] Production traffic switched to Green
- [ ] Browser shows Green Version 2
- [ ] Green failure simulated
- [ ] Traffic rolled back to Blue
- [ ] Browser shows Blue Version 1
- [ ] Docker logs inspected
- [ ] Nginx logs inspected
- [ ] Project documented in GitHub

---

# 22. Expected Final Result

The final project demonstrates:

```text
                    ForgePulse
                        |
                        v
                     Nginx
                        |
             +----------+----------+
             |                     |
             v                     v
        🔵 BLUE                 🟢 GREEN
        v1.0.0                  v2.0.0
        :8081                   :8082
             |                     |
             +----------+----------+
                        |
                      Docker
```

Blue-Green deployment provides:

- Separate production environments
- Safer releases
- Pre-production validation
- Minimal traffic interruption
- Fast rollback
- Repeatable deployments
- A foundation for CI/CD automation

---

## Learning Outcome

After completing this project, you should be able to explain:

1. What Blue-Green Deployment is.
2. Why two environments are used.
3. How Nginx controls traffic.
4. How Docker isolates application versions.
5. How health checks validate releases.
6. How a deployment is promoted to production.
7. How rollback works.
8. How Jenkins can automate the process.
9. How the same architecture can later be implemented with Kubernetes or cloud load balancers.

---

## Future Improvements

Possible next steps:

- Add Jenkins CI/CD
- Add automated unit tests
- Add automated rollback
- Add Prometheus/Grafana monitoring
- Add Docker Compose
- Add HTTPS with a local certificate
- Add a database
- Add Kubernetes Deployments
- Implement Canary Deployment
- Implement Rolling Deployment
- Recreate the architecture using AWS ECS/ALB later

---

## License

This project is intended for educational and DevOps practice purposes.
