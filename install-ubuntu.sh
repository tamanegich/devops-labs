#!/bin/bash
set -e

DB_NAME="taskdb"
DB_USER="taskuser"
DB_PASSWORD="taskpassword"
DB_PORT="3306"
APP_PORT="3000"
APP_USER="mywebapp"

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

require_root() {
    [ "$EUID" -eq 0 ] || error "please run as root: sudo bash install-ubuntu.sh"
}

install_packages() {
    info "updating package index..."
    apt-get update -y

    info "installing dependencies..."
    apt-get install -y ca-certificates curl gnupg nginx mariadb-server

    info "installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
}

create_users() {
    info "creating users..."

    if ! id student &>/dev/null; then
        useradd -m -G sudo student
        echo "student:123" | chpasswd
        info "created user: student"
    else
        info "user student already exists, skipping."
    fi

    if ! id teacher &>/dev/null; then
        useradd -m -G sudo teacher
        echo "teacher:12345678" | chpasswd
        chage -d 0 teacher
        info "created user: teacher"
    else
        info "user teacher already exists, skipping."
    fi

    if ! id operator &>/dev/null; then
        useradd -m operator
        echo "operator:12345678" | chpasswd
        chage -d 0 operator
        info "created user: operator"
    else
        info "user operator already exists, skipping."
    fi

    if ! id "$APP_USER" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
        info "created system user: $APP_USER"
    else
        info "user $APP_USER already exists, skipping."
    fi

    cat > /etc/sudoers.d/operator << 'EOF'
operator ALL=(ALL) NOPASSWD: /usr/bin/systemctl start mywebapp, \
                              /usr/bin/systemctl stop mywebapp, \
                              /usr/bin/systemctl restart mywebapp, \
                              /usr/bin/systemctl status mywebapp, \
                              /usr/bin/nginx -s reload
EOF
    chmod 440 /etc/sudoers.d/operator
    info "sudoers configured for operator."
}

setup_database() {
    info "setting up MariaDB..."
    systemctl enable mariadb
    systemctl start mariadb

    mariadb -u root << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME}
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    info "database and user created."
}

setup_docker() {
    info "configuring Docker..."
    systemctl enable docker
    systemctl start docker

    usermod -aG docker "$APP_USER"
    info "Docker configured."
}

setup_service() {
    info "installing systemd service for container..."

    cat > /etc/systemd/system/mywebapp.service << EOF
[Unit]
Description=Task Tracker Web App (container)
After=network.target docker.service mariadb.service
Requires=docker.service mariadb.service

[Service]
User=${APP_USER}
Restart=on-failure
RestartSec=5
ExecStartPre=-/usr/bin/docker stop mywebapp
ExecStartPre=-/usr/bin/docker rm mywebapp
ExecStart=/usr/bin/docker run --name mywebapp --rm \\
    --network host \\
    -e "NODE_ENV=production" \\
    ghcr.io/tamanegich/devops-labs:stable \\
    node server.js \\
    --port ${APP_PORT} \\
    --db-host localhost \\
    --db-port ${DB_PORT} \\
    --db-user ${DB_USER} \\
    --db-password ${DB_PASSWORD} \\
    --db-name ${DB_NAME}
ExecStop=/usr/bin/docker stop mywebapp

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mywebapp
    info "systemd service installed."
}

setup_nginx() {
    info "configuring nginx..."

    cat > /etc/nginx/sites-available/mywebapp << EOF
server {
    listen 80;
    server_name localhost;
    access_log /var/log/nginx/mywebapp_access.log;
    error_log  /var/log/nginx/mywebapp_error.log;

    location = / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location = /tasks {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location = /tasks/ {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location ~ ^/tasks/[^/]+/done$ {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location / {
        return 404;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp

    nginx -t || error "nginx config test failed"
    systemctl enable nginx
    systemctl restart nginx
    info "nginx configured and started."
}

block_default_user() {
    info "blocking default user accounts..."
    KEEP_USERS="root student teacher operator $APP_USER"
    while IFS=: read -r username _ uid _; do
        if [ "$uid" -ge 1000 ]; then
            keep=false
            for k in $KEEP_USERS; do
                [ "$username" = "$k" ] && keep=true && break
            done
            if [ "$keep" = false ]; then
                usermod -L "$username"
                info "locked user: $username"
            fi
        fi
    done < /etc/passwd
}

require_root
install_packages
create_users
setup_database
setup_docker
setup_service
setup_nginx
block_default_user

info "><>    =======================    <><"
info "        installation complete        "
info "><>    =======================    <><"