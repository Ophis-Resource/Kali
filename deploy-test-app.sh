#!/bin/bash

set -e

echo "=============================="
echo " SIMPLE FULL STACK APP SETUP"
echo "=============================="

PROJECT="$HOME/simple-app"

###################################
# INSTALL DEPENDENCIES
###################################

if ! command -v docker >/dev/null 2>&1; then
    echo "[INFO] Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo systemctl enable docker
    sudo systemctl start docker
fi

if ! command -v nginx >/dev/null 2>&1; then
    echo "[INFO] Installing Nginx..."
    sudo apt-get update -y
    sudo apt-get install -y nginx
fi

sudo systemctl enable nginx

###################################
# CLEAN OLD SETUP
###################################

rm -rf "$PROJECT"
mkdir -p "$PROJECT/backend"
mkdir -p "$PROJECT/frontend"

###################################
# BACKEND (FLASK)
###################################

cat > "$PROJECT/backend/app.py" <<'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/home")
def home():
    return jsonify({"page": "home"})

@app.route("/aboutus")
def aboutus():
    return jsonify({"page": "aboutus"})

@app.route("/admin")
def admin():
    return jsonify({"page": "admin"})

@app.route("/forbidden")
def forbidden():
    return jsonify({"page": "forbidden"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
EOF

cat > "$PROJECT/backend/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py .
RUN pip install flask
CMD ["python","app.py"]
EOF

###################################
# FRONTEND
###################################

cat > "$PROJECT/frontend/Dockerfile" <<'EOF'
FROM nginx:alpine
COPY . /usr/share/nginx/html/
EOF

for p in home aboutus admin forbidden; do
cat > "$PROJECT/frontend/$p.html" <<EOF
<!DOCTYPE html>
<html>
<head><title>$p</title></head>
<body style="text-align:center;font-family:Arial;margin-top:50px">

<h1>${p^^} PAGE</h1>

<a href="/home"><button>Home</button></a>
<a href="/aboutus"><button>About Us</button></a>
<a href="/admin"><button>Admin</button></a>
<a href="/forbidden"><button>Forbidden</button></a>

</body>
</html>
EOF
done

###################################
# BUILD IMAGES
###################################

echo "[INFO] Building backend..."
cd "$PROJECT/backend"
sudo docker build -t simple-backend .

echo "[INFO] Building frontend..."
cd "$PROJECT/frontend"
sudo docker build -t simple-frontend .

###################################
# RUN CONTAINERS (SAFE FIX)
###################################

sudo docker rm -f backend frontend 2>/dev/null || true

echo "[INFO] Starting backend..."
sudo docker run -d --name backend -p 8000:8000 simple-backend

echo "[INFO] Starting frontend..."
sudo docker run -d --name frontend -p 8080:80 simple-frontend

###################################
# NGINX CONFIG (NO BACKTICKS EVER)
###################################

sudo tee /etc/nginx/nginx.conf > /dev/null <<'EOF'
user www-data;
worker_processes auto;

events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    include /etc/nginx/conf.d/*.conf;
}
EOF

sudo tee /etc/nginx/conf.d/default.conf > /dev/null <<'EOF'
server {
    listen 5000;

    location = / {
        return 302 /home;
    }

    location = /home {
        proxy_pass http://127.0.0.1:8080/home.html;
    }

    location = /aboutus {
        proxy_pass http://127.0.0.1:8080/aboutus.html;
    }

    location = /admin {
        proxy_pass http://127.0.0.1:8080/admin.html;
    }

    location = /forbidden {
        proxy_pass http://127.0.0.1:8080/forbidden.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
    }
}
EOF

###################################
# RESTART NGINX
###################################

sudo nginx -t
sudo systemctl restart nginx

###################################
# DONE
###################################

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=============================="
echo " DEPLOYMENT COMPLETE"
echo "=============================="
echo ""
echo "OPEN:"
echo "http://$IP:5000/home"
echo "http://$IP:5000/aboutus"
echo "http://$IP:5000/admin"
echo "http://$IP:5000/forbidden"
echo ""
echo "API:"
echo "http://$IP:5000/api/home"
echo "http://$IP:5000/api/aboutus"
echo "http://$IP:5000/api/admin"
echo "http://$IP:5000/api/forbidden"
echo ""
echo "STATUS:"
sudo docker ps
echo "#############################"
