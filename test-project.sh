#!/bin/bash

set -e

# === COLORS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# === UTILS ===
info()    { echo -e "${YELLOW}[ [ [ INFO ] ] ] $1${NC}"; }
warn()    { echo -e "${RED}< < < WARN > > > $1${NC}"; }
success() { echo -e "${GREEN}< < < SUCCESSFUL > > > $1${NC}"; }

# === VARIABLES ===
PROJECT_ROOT=project-root
BACKEND_DIR=$PROJECT_ROOT/backend
FRONTEND_DIR=$PROJECT_ROOT/frontend
NGINX_DIR=$PROJECT_ROOT/nginx
SSL_DIR=$NGINX_DIR/ssl
LOGS_DIR=$NGINX_DIR/logs # Add logs directory
DOCKER_NETWORK=mynet

info "Starting project setup..."

# ==== STEP 1: Create directories ====
info "Creating project directory structure..."

mkdir -p $BACKEND_DIR
mkdir -p $FRONTEND_DIR/pages
mkdir -p $SSL_DIR
mkdir -p $LOGS_DIR  # Create logs directory inside nginx folder

success "Created directories."

# ==== STEP 2: Create backend files ====

info "Writing backend Dockerfile and app.py..."

cat > $BACKEND_DIR/Dockerfile <<'EOF'
FROM python:3.10-slim
WORKDIR /app
COPY app.py .
RUN pip install flask
EXPOSE 8080
CMD ["python", "app.py"]
EOF

cat > $BACKEND_DIR/app.py <<'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

paths = [
    "about", "About", "about_us", "aboutus", "about-us", "AboutUs",
    "abstract", "abuse", "ac"
]

@app.route("/")
def home():
    return jsonify({"message": "Backend is running"})

for path in paths:
    app.add_url_rule(f"/{path}", path, lambda path=path: jsonify({"route": path}))

# Custom error routes
@app.route("/admin")
@app.route("/admin/<path:path>")
def forbidden(path=None):
    return "Forbidden", 403

@app.errorhandler(404)
def not_found(e):
    return "Page not found (404)", 404

@app.errorhandler(405)
def method_not_allowed(e):
    return "Method not allowed (405)", 405

@app.errorhandler(415)
def unsupported_media_type(e):
    return "Unsupported Media Type (415)", 415

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

success "Backend files written."

# ==== STEP 3: Create frontend files ====

info "Writing frontend Dockerfile, index.html, and About page..."

cat > $FRONTEND_DIR/Dockerfile <<'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
COPY pages/ /usr/share/nginx/html/pages/
EXPOSE 80
EOF

cat > $FRONTEND_DIR/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Frontend</title></head>
<body>
  <h1>Frontend Placeholder</h1>
  <p>This is the frontend for the app.</p>
</body>
</html>
EOF

cat > $FRONTEND_DIR/pages/About.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>About</title></head>
<body>
  <h1>About page</h1>
  <p>This is the About page content.</p>
</body>
</html>
EOF

success "Frontend files written."

# ==== STEP 4: Create nginx config files ====

info "Writing nginx configuration files..."

cat > $NGINX_DIR/nginx.conf <<'EOF'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    # Update the access log and error log to use the logs directory
    access_log  /var/log/nginx/access.log  main;
    error_log  /var/log/nginx/error.log warn;

    sendfile        on;
    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > $NGINX_DIR/default.conf <<'EOF'
server {
    listen 80;
    server_name localhost;

    # Redirect HTTP to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name localhost;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log debug;

    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # FRONTEND: Serve frontend container on root
    location / {
        proxy_pass http://frontend:80;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SPA fallback (optional)
        error_page 404 = /index.html;
    }

    # BACKEND: Proxy API requests under /backend to backend container
    location /backend/ {
        proxy_pass http://backend:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # SECURITY: Block hidden files like .env
    location ~ /\.(?!well-known) {
        deny all;
    }

    error_page 502 /502.html;
    location = /502.html {
        internal;
        root /usr/share/nginx/html;
    }
}
EOF

success "Nginx configuration files written."

# ==== STEP 5: Generate SSL certs ====

info "Generating self-signed SSL certificates..."

if [ ! -f $SSL_DIR/nginx.crt ] || [ ! -f $SSL_DIR/nginx.key ]; then
  openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
    -keyout $SSL_DIR/nginx.key \
    -out $SSL_DIR/nginx.crt \
    -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=localhost" >/dev/null 2>&1
  success "SSL certificates generated."
else
  warn "SSL certificates already exist, skipping generation."
fi

# ==== STEP 6: Build docker images ====

info "Building backend docker image..."
sudo docker build -t my-backend $BACKEND_DIR

info "Building frontend docker image..."
sudo docker build -t my-frontend $FRONTEND_DIR

success "Docker images built."

# ==== STEP 7: Create docker network ====

info "Creating docker network: $DOCKER_NETWORK"

if sudo docker network ls | grep -q $DOCKER_NETWORK; then
    warn "Docker network '$DOCKER_NETWORK' already exists, skipping creation."
else
    sudo docker network create $DOCKER_NETWORK
    success "Docker network '$DOCKER_NETWORK' created."
fi

# ==== STEP 8: Run backend and frontend containers ====

info "Running backend container..."
sudo docker rm -f backend >/dev/null 2>&1 || true
sudo docker run -d --name backend --network $DOCKER_NETWORK -p 8080:8080 my-backend

info "Running frontend container..."
sudo docker rm -f frontend >/dev/null 2>&1 || true
sudo docker run -d --name frontend --network $DOCKER_NETWORK -p 8000:80 my-frontend

success "Backend and frontend containers are running."

# ==== STEP 9: Run nginx container ====

info "Running nginx reverse proxy container..."

sudo docker rm -f my-nginx >/dev/null 2>&1 || true

# Mount logs directory to persist logs
sudo docker run -d \
  --name my-nginx \
  --network $DOCKER_NETWORK \
  -p 80:80 -p 443:443 \
  -v $(pwd)/$NGINX_DIR/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/$NGINX_DIR/default.conf:/etc/nginx/conf.d/default.conf:ro \
  -v $(pwd)/$SSL_DIR:/etc/nginx/ssl:ro \
  -v $(pwd)/$LOGS_DIR:/var/log/nginx:rw \
  nginx:latest

success "Nginx container is running."

# ==== STEP 10: Final checks ====

info "Setup complete! Verify running containers with:"
echo "  sudo docker ps"

info "Test your app at:"
echo "  https://<your-vm-ip>/       (frontend)"
echo "  https://<your-vm-ip>/backend/  (backend API)"
echo "  http://<your-vm-ip>/        (should redirect to https)"

echo -e "\n=== ALL DONE ==="

exit 0


# curl -i http://localhost:8000/
# curl -i http://localhost/
# curl -i http://localhost:8000/
# curl -i http://localhost:8000/pages/About.html
# curl -i http://localhost:8080/
# curl -k -i https://localhost/
# curl -k -i https://localhost/pages/About.html
# curl -k -i https://localhost/api
# curl -i http://localhost:8080/
# curl -i http://localhost:8000/pages/About.html
# curl -k -i https://localhost/
# curl -k -i https://localhost/pages/About.html
# curl -k -i https://localhost/api
# curl -i http://localhost/
