#!/bin/bash
set -e

REPO_URL="https://github.com/tamanegich/devops-lab1.git"
APP_DIR="/opt/mywebapp"
DB_NAME="taskdb"
DB_USER="taskuser"
DB_PASSWORD="taskpassword"
DB_PORT="3306"
APP_PORT="3000"
APP_USER="mywebapp"

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

require_root() {
    [ "$EUID" -eq 0 ] || error "please run as root: sudo bash install.sh"
}

install_packages() {
    info "installing packages..."
    pacman -Sy --noconfirm nodejs npm mariadb nginx git
}

create_users() {
    info "creating users..."

    if ! id student &>/dev/null; then
        useradd -m -G wheel student
        echo "student:123" | chpasswd
        info "created user: student"
    else
        info "user student already exists, skipping."
    fi

    if ! id teacher &>/dev/null; then
        useradd -m -G wheel teacher
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
        useradd --system --no-create-home --shell /usr/bin/nologin "$APP_USER"
        info "created system user: $APP_USER"
    else
        info "user $APP_USER already exists, skipping."
    fi

    if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
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
    if [ ! -d /var/lib/mysql/mysql ]; then
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    fi
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

setup_app() {
    info "cloning repository..."
    if [ -d "$APP_DIR" ]; then
        rm -rf "$APP_DIR"
    fi
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
    npm install --omit=dev
    chown -R "$APP_USER":"$APP_USER" "$APP_DIR"
    info "app installed to $APP_DIR."
}

setup_service() {
    info "installing systemd service..."
    SERVICE_SRC=""
    if [ -f "$APP_DIR/mywebapp.service" ]; then
        SERVICE_SRC="$APP_DIR/mywebapp.service"
    elif [ -f "$(dirname "$0")/mywebapp.service" ]; then
        SERVICE_SRC="$(dirname "$0")/mywebapp.service"
    else
      error "mywebapp.service not found in repo or next to install.sh"
    fi

    sed \
        -e "s|/opt/mywebapp|${APP_DIR}|g" \
        -e "s|--db-port 3306|--db-port ${DB_PORT}|g" \
        -e "s|--db-user taskuser|--db-user ${DB_USER}|g" \
        -e "s|--db-password taskpassword|--db-password ${DB_PASSWORD}|g" \
        -e "s|--db-name taskdb|--db-name ${DB_NAME}|g" \
        -e "s|--port 3000|--port ${APP_PORT}|g" \
        "$SERVICE_SRC" > /etc/systemd/system/mywebapp.service

    systemctl daemon-reload
    systemctl enable mywebapp
    info "systemd service installed."
}

setup_nginx() {
    info "configuring nginx..."

    mkdir -p /etc/nginx/conf.d

    if ! grep -q "include /etc/nginx/conf.d/\*\.conf" /etc/nginx/nginx.conf; then
      sed -i '/^http {/a\    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
    fi

    NGINX_SRC=""
    if [ -f "$APP_DIR/mywebapp.conf" ]; then
        NGINX_SRC="$APP_DIR/mywebapp.conf"
    elif [ -f "$(dirname "$0")/mywebapp.conf" ]; then
        NGINX_SRC="$(dirname "$0")/mywebapp.conf"
    else
        error "mywebapp.conf not found in repo or next to install.sh"
    fi

    sed "s|127.0.0.1:3000|127.0.0.1:${APP_PORT}|g" "$NGINX_SRC" \
        > /etc/nginx/conf.d/mywebapp.conf

    nginx -t || error "nginx config test failed"
    systemctl enable nginx
    systemctl restart nginx
    info "nginx configured and started."
}

start_app() {
    info "starting mywebapp service..."
    systemctl start mywebapp
    systemctl status mywebapp --no-pager
}

create_gradebook() {
    info "creating gradebook..."
    mkdir -p /home/student
    echo "22" > /home/student/gradebook
    chown student:student /home/student/gradebook
    info "gradebook created at /home/student/gradebook."
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
                info "Locked user: $username"
            fi
        fi
    done < /etc/passwd
}

require_root
install_packages
create_users
setup_database
setup_app
setup_service
setup_nginx
start_app
create_gradebook
block_default_user

info "><>    =======================    <><"
info "        installation complete        "
info "><>    =======================    <><"
