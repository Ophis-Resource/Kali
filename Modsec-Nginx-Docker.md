
# NGINX with ModSecurity Docker Container

This project provides a Docker container running NGINX with ModSecurity enabled. It includes building ModSecurity from source and allows mounting custom NGINX configuration files from the host.

---

## Dockerfile Overview

- Base image: `nginx:latest`
- Installs necessary build tools and dependencies
- Copies and runs a ModSecurity install script (`modsecinstall.sh`)
- Exposes port 80
- Runs NGINX in the foreground

---

## Building the Docker Image

Build the container image with the following command:

```bash
docker build -t nginx-modsec .
````

---

## Running the Container with External Configs

Assuming you have your NGINX config files on the host at:

* `~/nginx-config/nginx.conf`
* `~/nginx-config/default.conf`

Run the container with these configs mounted as read-only:

```bash
docker run -d -p 80:80 \
  -v ~/nginx-config/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v ~/nginx-config/default.conf:/etc/nginx/conf.d/default.conf:ro \
  --name nginx-modsec-container \
  nginx-modsec
```

* `:ro` makes the mounts read-only, which is safer for configs.
* This overrides the container's default NGINX configuration with your custom configs.

---

## Managing NGINX inside the Container

### Test Configuration

To test your NGINX configuration inside the running container:

```bash
docker exec -it nginx-modsec-container nginx -t
```

### Reload NGINX

If the test is successful, reload NGINX with:

```bash
docker exec nginx-modsec-container nginx -s reload
```

---

## Bonus: Shell Script to Test and Reload NGINX

Create a file named `nginx-reload.sh` with the following content:

```bash
#!/bin/bash

CONTAINER_NAME="nginx-modsec-container"

echo "Testing NGINX configuration..."
docker exec -it $CONTAINER_NAME nginx -t

if [ $? -eq 0 ]; then
  echo "Configuration OK. Reloading NGINX..."
  docker exec $CONTAINER_NAME nginx -s reload
else
  echo "Configuration test failed. Not reloading."
fi
```

Make it executable:

```bash
chmod +x nginx-reload.sh
```

Run it to safely test and reload NGINX inside your container.

---
