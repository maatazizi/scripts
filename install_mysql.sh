#!/bin/bash

set -euo pipefail

########################################

# VARIABLES

########################################

INSTALLER_PATH="/opt/installers"

OLD_DATADIR="/var/lib/mysql"
NEW_DATADIR="/mysqldata/mysql"
NEW_TEMDIR="/mysqldata/mysql/tmps"
NEW_LOGDIR="/mysqldata/logs"


MYSQL_ROOT_PASSWORD='P@ssw0rdMsql'
RESET_ROOT_PASSWORD='YES'

LOGFILE="/var/log/mysql_install_$(date +%Y%m%d_%H%M%S).log"

########################################

# LOGGING

########################################

exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "========================================"
echo " MySQL Commercial Installation"
echo "========================================"

########################################

# PRECHECK

########################################

if [[ $EUID -ne 0 ]]; then
echo "ERROR: Please run as root."
exit 1
fi

source /etc/os-release

if [[ ! "${VERSION_ID}" =~ ^9 ]]; then
echo "ERROR: EL9 only."
exit 1
fi

if [[ ! -d "$INSTALLER_PATH" ]]; then
echo "ERROR: Installer path not found."
exit 1
fi

RPM_COUNT=$(find "$INSTALLER_PATH" -maxdepth 1 -name "mysql-commercial-*.rpm" | wc -l)

if [[ "$RPM_COUNT" -eq 0 ]]; then
echo "ERROR: No MySQL RPM found."
exit 1
fi

echo "Found $RPM_COUNT RPM package(s)."

########################################

# STORAGE CHECK

########################################

mkdir -p /mysqldata

AVAILABLE_GB=$(df -BG /mysqldata | awk 'NR==2 {gsub("G","",$4); print $4}')

if [[ "$AVAILABLE_GB" -lt 10 ]]; then
echo "ERROR: Less than 10GB free space."
exit 1
fi

########################################

# IMPORT MYSQL GPG KEY

########################################

if [[ -f "${INSTALLER_PATH}/RPM-GPG-KEY-mysql-2023" ]]; then
rpm --import "${INSTALLER_PATH}/RPM-GPG-KEY-mysql-2023"
fi

########################################

# DEPENDENCY CHECK

########################################

if ls ${INSTALLER_PATH}/mysql-commercial-devel-*.rpm >/dev/null 2>&1; then


if ! rpm -q openssl-devel >/dev/null 2>&1; then
    dnf install -y openssl-devel
fi


fi

########################################

# INSTALL MYSQL

########################################

if rpm -qa | grep -q mysql-commercial-server; then
echo "MySQL already installed."
else
echo "Installing MySQL Commercial..."
dnf localinstall -y ${INSTALLER_PATH}/mysql-commercial-*.rpm
fi

########################################

# START MYSQL

########################################

systemctl enable mysqld
systemctl start mysqld

sleep 10

########################################

# RESET ROOT PASSWORD

########################################

if [[ "${RESET_ROOT_PASSWORD^^}" == "YES" ]]; then


echo "Resetting root password..."

TEMP_PASSWORD=$(grep "temporary password" /var/log/mysqld.log 2>/dev/null | tail -1 | awk '{print $NF}')

if [[ -z "${TEMP_PASSWORD}" ]]; then
    echo "ERROR: Unable to locate temporary password."
    exit 1
fi

MYSQL_PWD="${TEMP_PASSWORD}" \
mysql --connect-expired-password \
      -uroot \
      -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"

echo "Root password updated."

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" \
      -e "SELECT VERSION();" >/dev/null

echo "Root login verified."


else


echo "Password reset skipped."


fi

########################################

# PREVENT RE-RUN MIGRATION

########################################

if [[ -f ${NEW_DATADIR}/auto.cnf ]]; then


echo ""
echo "WARNING: Migration already completed."
echo "Detected existing MySQL datadir: ${NEW_DATADIR}"

exit 0


fi

########################################

# STOP MYSQL

########################################

systemctl stop mysqld

########################################

# CREATE DIRECTORIES

########################################

mkdir -p ${NEW_DATADIR}
mkdir -p ${NEW_LOGDIR}
mkdir -p ${NEW_TEMDIR}

########################################

# MIGRATE DATA

########################################

echo "Migrating datadir..."

rsync -aHAX ${OLD_DATADIR}/ ${NEW_DATADIR}/

sync

########################################

# PERMISSIONS

########################################

chown -R mysql:mysql ${NEW_DATADIR}
chown -R mysql:mysql ${NEW_LOGDIR}

########################################

# BACKUP CONFIG

########################################

cp -p /etc/my.cnf /etc/my.cnf.bak.$(date +%F_%H%M%S)

########################################

# UPDATE CONFIG

########################################

grep -q "^datadir=${NEW_DATADIR}$" /etc/my.cnf || \
sed -i "/^\[mysqld\]/a datadir=${NEW_DATADIR}" /etc/my.cnf

if ! grep -q "log_error=${NEW_LOGDIR}/mysqld.log" /etc/my.cnf; then

cat <<EOF >> /etc/my.cnf

# Custom Log Location

log_error=${NEW_LOGDIR}/mysqld.log

slow_query_log=1
slow_query_log_file=${NEW_LOGDIR}/slow.log

general_log=0
general_log_file=${NEW_LOGDIR}/general.log

EOF

fi

########################################

# SELINUX

########################################

if command -v getenforce >/dev/null 2>&1; then


if [[ "$(getenforce)" != "Disabled" ]]; then

    dnf install -y policycoreutils-python-utils >/dev/null 2>&1 || true

    semanage fcontext -a -t mysqld_db_t "${NEW_DATADIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t mysqld_db_t "${NEW_DATADIR}(/.*)?"

    semanage fcontext -a -t mysqld_log_t "${NEW_LOGDIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t mysqld_log_t "${NEW_LOGDIR}(/.*)?"

    restorecon -Rv /mysqldata

fi


fi

########################################

# START MYSQL AGAIN

########################################

systemctl start mysqld

sleep 10

for i in {1..30}; do
    mysqladmin ping >/dev/null 2>&1 && break
    sleep 1
done

########################################

# VERIFY SERVICE

########################################

if ! systemctl is-active --quiet mysqld; then


echo "ERROR: MySQL failed to start."

if [[ -f ${NEW_LOGDIR}/mysqld.log ]]; then
    tail -50 ${NEW_LOGDIR}/mysqld.log
else
    journalctl -u mysqld -n 50 --no-pager
fi

exit 1


fi

########################################

# VERIFY LOGIN & DATADIR

########################################
echo "Verifying MySQL datadir..."

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" \
-e "SELECT VERSION(), @@hostname, @@datadir\G"

echo "MySQL verification completed."

########################################

# FINAL OUTPUT

########################################

echo ""
echo "========================================"
echo "MYSQL INSTALLATION COMPLETED"
echo "========================================"

echo "Hostname  : $(hostname)"
echo "Datadir   : ${NEW_DATADIR}"
echo "Logdir    : ${NEW_LOGDIR}"
echo "Username  : root"
echo "Password  : ${MYSQL_ROOT_PASSWORD}"

echo ""
echo "DBA ACTION REQUIRED:"
echo "1. Login using root account"
echo "2. Change root password"
echo "3. Validate application connectivity"

echo ""
echo "Installation Log:"
echo "$LOGFILE"

echo ""
echo "Done."
