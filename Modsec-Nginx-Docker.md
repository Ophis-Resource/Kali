
# NGINX with ModSecurity Docker Container

This repository provides a Docker container setup that runs NGINX with ModSecurity enabled. ModSecurity is installed from source during the container build, along with necessary dependencies.

---

## Dockerfile

```dockerfile
# Base image: Official NGINX
FROM nginx:latest

# Install necessary build tools and dependencies
RUN apt-get update && apt-get install -y \
    build-essential autoconf automake libtool pkg-config git wget curl \
    zlib1g-dev libpcre2-dev libxml2-dev libcurl4-openssl-dev liblua5.3-dev \
    libpcre2-dev libssl-dev libxslt1-dev libgd-dev libgeoip-dev \
    libperl-dev libmaxminddb-dev \
 && rm -rf /var/lib/apt/lists/*

# Copy and run the ModSecurity install script
COPY modsecinstall.sh /home/modsecinstall.sh

RUN chmod +x /home/modsecinstall.sh && \
    /home/modsecinstall.sh

# Optional: expose ports (default NGINX ports)
EXPOSE 80

# Default command
CMD ["nginx", "-g", "daemon off;"]
````

---

## Building the Docker Image

Run this command in the directory containing your Dockerfile and `modsecinstall.sh`:

```bash
docker build -t nginx-modsec .
```

---

## Running the Container with External Configs

Assuming your host has NGINX configuration files here:

* `~/nginx-config/nginx.conf`
* `~/nginx-config/default.conf`

Run the container with these configs mounted (read-only):

```bash
docker run -d -p 80:80 \
  -v ~/nginx-config/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v ~/nginx-config/default.conf:/etc/nginx/conf.d/default.conf:ro \
  --name nginx-modsec-container \
  nginx-modsec
```

* `:ro` makes mounts read-only (safer for config files).
* This will override the container's default configs with your custom ones.

---

## Managing NGINX Configuration Inside the Container

### Test Configuration

To verify your configs inside the container:

```bash
docker exec -it nginx-modsec-container nginx -t
```

### Reload NGINX

After a successful test, reload NGINX to apply changes:

```bash
docker exec nginx-modsec-container nginx -s reload
```

---

## Bonus: Quick Shell Script to Test and Reload NGINX

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

Run it anytime you want to safely test and reload NGINX inside the container:

```bash
./nginx-reload.sh
```

