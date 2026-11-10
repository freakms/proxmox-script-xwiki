#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 freakms and contributors
#
# xwiki-install.sh - Install XWiki on Debian (Tomcat 10 + PostgreSQL/MariaDB)
# from the official XWiki APT repository (https://maven.xwiki.org).
#
# Normally called by xwiki-lxc.sh inside a freshly created container, but it
# can also be run by hand on any Debian 13 (trixie) system:
#   DB=pgsql XWIKI_CHANNEL=stable bash xwiki-install.sh
#
# Project: https://github.com/freakms/proxmox-script-xwiki

set -Eeuo pipefail

DB="${DB:-pgsql}"                       # pgsql | mariadb
XWIKI_CHANNEL="${XWIKI_CHANNEL:-stable}" # stable | lts
JAVA_XMX="${JAVA_XMX:-}"                # MiB, default: 60% of RAM

XWIKI_REPO_URL="https://maven.xwiki.org"
XWIKI_KEY_URL="${XWIKI_REPO_URL}/xwiki-keyring.gpg"
XWIKI_KEYRING="/usr/share/keyrings/xwiki-archive-keyring.gpg"
XWIKI_LIST="/etc/apt/sources.list.d/xwiki.list"
TOMCAT="tomcat10"

msg_info()  { echo "  [INFO]  $*"; }
msg_ok()    { echo "  [ OK ]  $*"; }
msg_warn()  { echo "  [WARN]  $*" >&2; }
die()       { echo "  [FAIL]  $*" >&2; exit 1; }
trap 'die "Installer aborted in line ${LINENO}."' ERR

[[ "$(id -u)" -eq 0 ]] || die "Run as root."
[[ "${DB}" == "pgsql" || "${DB}" == "mariadb" ]] || die "DB must be pgsql or mariadb."
[[ "${XWIKI_CHANNEL}" == "stable" || "${XWIKI_CHANNEL}" == "lts" ]] || die "XWIKI_CHANNEL must be stable or lts."

# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID}" == "debian" ]] || die "Only Debian is supported (found: ${ID})."
DEBIAN_MAJOR="${VERSION_ID%%.*}"
if [[ "${XWIKI_CHANNEL}" == "stable" && "${DEBIAN_MAJOR}" -lt 13 ]]; then
  die "XWiki stable (18.x) requires Java 21 -> Debian 13 or newer. Use XWIKI_CHANNEL=lts on Debian ${VERSION_ID}."
fi
[[ "${DEBIAN_MAJOR}" -ge 12 ]] || die "Debian 12 or newer is required (Tomcat 10)."

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# ---------------------------------------------------------------------------
# Base system
# ---------------------------------------------------------------------------
msg_info "Updating the operating system"
apt-get update -q >/dev/null
apt-get "${APT_OPTS[@]}" dist-upgrade >/dev/null
apt-get "${APT_OPTS[@]}" install curl ca-certificates gnupg locales >/dev/null
msg_ok "Operating system updated"

# ---------------------------------------------------------------------------
# Database server (installed first so dbconfig-common can create the DB)
# ---------------------------------------------------------------------------
if [[ "${DB}" == "pgsql" ]]; then
  msg_info "Installing PostgreSQL"
  apt-get "${APT_OPTS[@]}" install postgresql >/dev/null
  systemctl enable --now postgresql >/dev/null 2>&1
  msg_ok "PostgreSQL installed"
else
  msg_info "Installing MariaDB"
  apt-get "${APT_OPTS[@]}" install mariadb-server >/dev/null
  systemctl enable --now mariadb >/dev/null 2>&1
  msg_ok "MariaDB installed"
fi

# ---------------------------------------------------------------------------
# XWiki APT repository
# ---------------------------------------------------------------------------
msg_info "Adding the XWiki APT repository (${XWIKI_CHANNEL})"
TMP_KEY="$(mktemp)"
curl -fsSL "${XWIKI_KEY_URL}" -o "${TMP_KEY}"
if grep -q -- "-----BEGIN PGP PUBLIC KEY BLOCK-----" "${TMP_KEY}"; then
  gpg --dearmor --yes -o "${XWIKI_KEYRING}" "${TMP_KEY}"
else
  install -m 0644 "${TMP_KEY}" "${XWIKI_KEYRING}"
fi
rm -f "${TMP_KEY}"
chmod 0644 "${XWIKI_KEYRING}"
echo "deb [signed-by=${XWIKI_KEYRING}] ${XWIKI_REPO_URL} ${XWIKI_CHANNEL}/all/" > "${XWIKI_LIST}"
apt-get update -q >/dev/null
msg_ok "XWiki repository added"

# ---------------------------------------------------------------------------
# XWiki package
# ---------------------------------------------------------------------------
pkg_available() {
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" {found=1} END {exit !found}'
}

XWIKI_PKG="xwiki-${TOMCAT}-${DB}"
if ! pkg_available "${XWIKI_PKG}"; then
  if [[ "${DB}" == "mariadb" ]] && pkg_available "xwiki-${TOMCAT}-mysql"; then
    XWIKI_PKG="xwiki-${TOMCAT}-mysql"
  else
    die "Package ${XWIKI_PKG} is not available in the XWiki ${XWIKI_CHANNEL} repository."
  fi
fi

# Let dbconfig-common create the database and a random password unattended.
debconf-set-selections <<EOF
dbconfig-common dbconfig-common/dbconfig-install boolean true
dbconfig-common dbconfig-common/remember-admin-pass boolean false
EOF

msg_info "Installing ${XWIKI_PKG} $(apt-cache policy "${XWIKI_PKG}" | awk '/Candidate:/ {print $2}')"
apt-get "${APT_OPTS[@]}" install "${XWIKI_PKG}" >/dev/null
msg_ok "XWiki installed"

# ---------------------------------------------------------------------------
# Tomcat tuning (Debian's default heap is far too small for XWiki)
# ---------------------------------------------------------------------------
if [[ -z "${JAVA_XMX}" ]]; then
  MEM_MB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))
  JAVA_XMX=$(( MEM_MB * 60 / 100 ))
fi
[[ "${JAVA_XMX}" -ge 1024 ]] || JAVA_XMX=1024

DEFAULTS_FILE="/etc/default/${TOMCAT}"
touch "${DEFAULTS_FILE}"
# Remove a previous block of this script and disable other JAVA_OPTS lines.
sed -i '/^# BEGIN proxmox-script-xwiki/,/^# END proxmox-script-xwiki/d' "${DEFAULTS_FILE}"
sed -i 's/^\(JAVA_OPTS=.*\)$/#\1  # disabled by proxmox-script-xwiki/' "${DEFAULTS_FILE}"
cat >> "${DEFAULTS_FILE}" <<EOF
# BEGIN proxmox-script-xwiki
JAVA_OPTS="-Djava.awt.headless=true -Xmx${JAVA_XMX}m -XX:+UseG1GC"
# END proxmox-script-xwiki
EOF
msg_ok "Tomcat heap set to ${JAVA_XMX} MiB"

msg_info "Restarting ${TOMCAT}"
systemctl enable "${TOMCAT}" >/dev/null 2>&1
systemctl restart "${TOMCAT}"

msg_info "Waiting for XWiki to answer on port 8080 (can take a few minutes)"
HTTP_CODE="000"
for _ in $(seq 1 90); do
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/xwiki/ || true)"
  [[ "${HTTP_CODE}" =~ ^(200|302|303)$ ]] && break
  sleep 5
done
if [[ "${HTTP_CODE}" =~ ^(200|302|303)$ ]]; then
  msg_ok "XWiki responds (HTTP ${HTTP_CODE})"
else
  msg_warn "XWiki did not answer yet (HTTP ${HTTP_CODE}). Check: journalctl -u ${TOMCAT}"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
apt-get -y -q autoremove >/dev/null
apt-get -y -q clean
rm -f "$0" 2>/dev/null || true
msg_ok "Installation finished"
