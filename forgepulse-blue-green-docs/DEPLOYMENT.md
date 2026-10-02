# ForgePulse Deployment and Rollback Guide

## Environment

This guide assumes:

```text
OS: Ubuntu
Application: Flask
Container: Docker
Reverse Proxy: Nginx
Blue Port: 8081
Green Port: 8082
Production Port: 80
```

---

# Deployment Procedure

## Step 1: Check Blue

```bash
docker ps
curl http://localhost:8081/health
```

Confirm Blue is healthy.

---

## Step 2: Build the New Version

Update:

```python
VERSION = "2.0.0"
ENVIRONMENT = "GREEN"
```

Build:

```bash
docker build -t forgepulse:2.0 ./app
```

---

## Step 3: Deploy Green

```bash
docker rm -f forgepulse-green 2>/dev/null || true
```

Then:

```bash
docker run -d \
  --name forgepulse-green \
  -p 8082:5000 \
  forgepulse:2.0
```

---

## Step 4: Validate Green

```bash
curl http://localhost:8082/health
```

Check:

```bash
curl -I http://localhost:8082
```

Run repeated health checks:

```bash
for i in {1..5}; do
    curl -s http://localhost:8082/health
    echo
done
```

---

## Step 5: Switch Traffic

Edit:

```bash
sudo nano /etc/nginx/sites-available/forgepulse
```

Use:

```nginx
upstream forgepulse_backend {
    server 127.0.0.1:8082;
}
```

Test:

```bash
sudo nginx -t
```

Reload:

```bash
sudo systemctl reload nginx
```

---

## Step 6: Verify Production

```bash
curl http://localhost
```

Open in browser:

```text
http://localhost
```

Confirm:

```text
GREEN ENVIRONMENT
Version 2.0.0
```

---

# Rollback Procedure

## Step 1: Detect Problem

Examples:

```text
HTTP errors
Application failure
Broken feature
Failed health checks
Unexpected application behavior
```

---

## Step 2: Point Nginx Back to Blue

Edit:

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

---

## Step 3: Validate Nginx

```bash
sudo nginx -t
```

---

## Step 4: Reload Nginx

```bash
sudo systemctl reload nginx
```

---

## Step 5: Verify Rollback

```bash
curl http://localhost
```

Expected:

```text
BLUE ENVIRONMENT
Version 1.0.0
```

---

# Troubleshooting

## Check containers

```bash
docker ps -a
```

## Check Blue logs

```bash
docker logs forgepulse-blue
```

## Check Green logs

```bash
docker logs forgepulse-green
```

## Check Nginx status

```bash
sudo systemctl status nginx
```

## Check Nginx configuration

```bash
sudo nginx -t
```

## Check Nginx access logs

```bash
sudo tail -f /var/log/nginx/access.log
```

## Check Nginx errors

```bash
sudo tail -f /var/log/nginx/error.log
```

## Check ports

```bash
sudo ss -lntp
```

Expected relevant ports:

```text
:80
:8081
:8082
```

---

# Deployment Verification Checklist

Before promotion:

- [ ] Green container is running
- [ ] Green `/health` returns success
- [ ] Green returns expected version
- [ ] Green returns expected environment
- [ ] Blue is still serving production traffic
- [ ] Nginx configuration passes validation

After promotion:

- [ ] Production URL returns Green
- [ ] Browser shows Version 2
- [ ] Green logs show requests
- [ ] Nginx access logs show requests
- [ ] Blue remains available for rollback

After rollback:

- [ ] Nginx points to Blue
- [ ] Nginx configuration passes validation
- [ ] Production URL returns Blue
- [ ] Blue health check succeeds
- [ ] Failed Green release is isolated
