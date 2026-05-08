#!/bin/bash

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "Sila run sebagai root atau guna sudo"
  exit 1
fi

# Input username
read -p "Masukkan username: " USERNAME

if [ -z "$USERNAME" ]; then
  echo "Username tak boleh kosong!"
  exit 1
fi

# Check user exist
if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' sudah wujud!"
  exit 1
fi

# Input password
read -s -p "Masukkan password: " PASSWORD
echo
read -s -p "Confirm password: " PASSWORD2
echo

if [ "$PASSWORD" != "$PASSWORD2" ]; then
  echo "Password tak sama!"
  exit 1
fi

# Input folder
read -p "Masukkan path folder (contoh: /data/project): " FOLDER

if [ -z "$FOLDER" ]; then
  echo "Folder path tak boleh kosong!"
  exit 1
fi

# Input group
read -p "Masukkan primary group (default: apache): " GROUP
GROUP=${GROUP:-apache}

if ! getent group "$GROUP" > /dev/null; then
  echo "Group '$GROUP' tak wujud!"
  exit 1
fi

# Create user
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Set primary group
usermod -g "$GROUP" "$USERNAME"

# 🔥 OPTIONAL: set home directory ke /var/www/apps/<user>

# Kill process kalau user aktif (just in case)
pkill -u "$USERNAME" 2>/dev/null

usermod -d "$FOLDER" "$USERNAME"

# Create folder kalau tak wujud
if [ ! -d "$FOLDER" ]; then
  mkdir -p "$FOLDER"
  echo "Folder $FOLDER telah dibuat"
fi

# Ownership
chown "$GROUP":"$GROUP" "$FOLDER"

# ACL normal
setfacl -m u:$USERNAME:rwx "$FOLDER"

# ACL default
setfacl -d -m u:$USERNAME:rwx "$FOLDER"

# 🔥 ACL recursive (yang kau nak)
setfacl -R -m u:$USERNAME:rwx "$FOLDER"

# Sudo option
read -p "Nak bagi sudo access? (y/n): " SUDO
if [[ "$SUDO" =~ ^[Yy]$ ]]; then
  usermod -aG wheel "$USERNAME"
fi

echo "----------------------------------------"
echo "User '$USERNAME' berjaya dicipta!"
echo "Primary group: $GROUP"
echo "Folder: $FOLDER"
echo "Home dir: $APP_HOME"
echo "----------------------------------------"

id "$USERNAME"
