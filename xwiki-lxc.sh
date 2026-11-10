#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 freakms and contributors
#
# xwiki-lxc.sh - Create a Debian LXC container on a Proxmox VE host and
# install XWiki (Tomcat 10 + PostgreSQL or MariaDB) inside it, using the
# official XWiki Debian packages from https://maven.xwiki.org.
#
# This script does NOT ship or redistribute XWiki. It only downloads XWiki
# from its official package repository. XWiki itself is licensed under the
# GNU LGPL v2.1 - see THIRD_PARTY_NOTICES.md.
#
# Project: https://github.com/freakms/proxmox-script-xwiki
#
# Usage (on the Proxmox VE host, as root):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/freakms/proxmox-script-xwiki/main/xwiki-lxc.sh)"
#
# Every setting can be preset through an environment variable (see README.md),
# e.g.:  CTID=150 RAM=6144 DB=mariadb ./xwiki-lxc.sh --yes

set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/freakms/proxmox-script-xwiki/main}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[36m'; C_BOLD=$'\e[1m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi
msg_info()  { echo "${C_BLUE}[INFO]${C_RESET}  $*"; }
msg_ok()    { echo "${C_GREEN}[ OK ]${C_RESET}  $*"; }
msg_warn()  { echo "${C_YELLOW}[WARN]${C_RESET}  $*" >&2; }
msg_error() { echo "${C_RED}[FAIL]${C_RESET}  $*" >&2; }
die()       { msg_error "$*"; exit 1; }

CT_CREATED=0
on_error() {
  local exit_code=$? line=$1
  msg_error "Aborted in line ${line} (exit code ${exit_code})."
  if [[ "${CT_CREATED}" == "1" ]]; then
    msg_warn "Container ${CTID} was created but the installation did not finish."
    msg_warn "Inspect it with 'pct enter ${CTID}' or remove it with 'pct stop ${CTID}; pct destroy ${CTID}'."
  fi
  exit "${exit_code}"
}
trap 'on_error ${LINENO}' ERR

usage() {
  cat <<EOF
xwiki-lxc.sh ${SCRIPT_VERSION} - XWiki LXC installer for Proxmox VE

Usage: $0 [--yes] [--help]

  -y, --yes    Do not ask questions; use defaults / environment variables.
  -h, --help   Show this help.

Environment variables (defaults in brackets):
  CTID             Container ID                         [next free ID]
  CT_HOSTNAME      Hostname                             [xwiki]
  CORES            CPU cores                            [2]
  RAM              Memory in MiB                        [4096]
  SWAP             Swap in MiB                          [512]
  DISK             Root disk size in GiB                [16]
  STORAGE          Storage for the root disk            [first storage with 'rootdir']
  TEMPLATE_STORAGE Storage for the OS template          [first storage with 'vztmpl']
  BRIDGE           Network bridge                       [vmbr0]
  IP               'dhcp' or CIDR, e.g. 192.168.1.50/24 [dhcp]
  GATEWAY          Gateway (only for static IP)         []
  DNS              DNS server(s), space separated       [host settings]
  VLAN             VLAN tag                             []
  UNPRIVILEGED     1 = unprivileged container           [1]
  CT_PASSWORD      Root password for the container      [none - use 'pct enter']
  SSH_KEY_FILE     Public key file for root login       []
  DB               Database: pgsql | mariadb            [pgsql]
  XWIKI_CHANNEL    XWiki repository: stable | lts       [stable]
  JAVA_XMX         Java max heap in MiB                 [about 60% of RAM]
EOF
}

ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Unknown option: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "Please run this script as root on the Proxmox VE host."
command -v pveversion >/dev/null 2>&1 || die "This does not look like a Proxmox VE host (pveversion not found)."
for bin in pct pveam pvesm pvesh; do
  command -v "${bin}" >/dev/null 2>&1 || die "Required command '${bin}' not found."
done

PVE_MAJOR="$(pveversion | sed -n 's|^pve-manager/\([0-9]\+\).*|\1|p')"
if [[ -n "${PVE_MAJOR}" && "${PVE_MAJOR}" -lt 8 ]]; then
  die "Proxmox VE 8 or newer is required (found: $(pveversion))."
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
first_storage_with() {
  # Print the first active storage that supports the given content type.
  pvesm status -content "$1" 2>/dev/null | awk 'NR>1 && $3=="active" {print $1; exit}'
}

CTID="${CTID:-$(pvesh get /cluster/nextid)}"
CT_HOSTNAME="${CT_HOSTNAME:-xwiki}"
CORES="${CORES:-2}"
RAM="${RAM:-4096}"
SWAP="${SWAP:-512}"
DISK="${DISK:-16}"
STORAGE="${STORAGE:-$(first_storage_with rootdir)}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-$(first_storage_with vztmpl)}"
BRIDGE="${BRIDGE:-vmbr0}"
IP="${IP:-dhcp}"
GATEWAY="${GATEWAY:-}"
DNS="${DNS:-}"
VLAN="${VLAN:-}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
CT_PASSWORD="${CT_PASSWORD:-}"
SSH_KEY_FILE="${SSH_KEY_FILE:-}"
DB="${DB:-pgsql}"
XWIKI_CHANNEL="${XWIKI_CHANNEL:-stable}"
JAVA_XMX="${JAVA_XMX:-}"

ask() {
  # ask VAR "Question"  -> reads a value, keeps the current value on <Enter>
  local __var=$1 __question=$2 __reply
  [[ "${ASSUME_YES}" == "1" ]] && return 0
  read -r -p "${__question} [${!__var}]: " __reply </dev/tty || true
  [[ -n "${__reply}" ]] && printf -v "${__var}" '%s' "${__reply}"
  return 0
}

echo
echo "${C_BOLD}XWiki LXC installer for Proxmox VE (v${SCRIPT_VERSION})${C_RESET}"
echo "XWiki is free software (LGPL-2.1) by the XWiki community - https://www.xwiki.org"
echo "This project is not affiliated with XWiki SAS or Proxmox Server Solutions GmbH."
echo

ask CTID          "Container ID"
ask CT_HOSTNAME   "Hostname"
ask CORES         "CPU cores"
ask RAM           "Memory (MiB)"
ask DISK          "Disk size (GiB)"
ask STORAGE       "Storage for root disk"
ask BRIDGE        "Network bridge"
ask IP            "IPv4 address (dhcp or CIDR)"
if [[ "${IP}" != "dhcp" ]]; then
  ask GATEWAY     "Gateway"
fi
ask DB            "Database (pgsql/mariadb)"
ask XWIKI_CHANNEL "XWiki channel (stable/lts)"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }
is_int "${CTID}"  && [[ "${CTID}" -ge 100 ]] || die "Invalid container ID: ${CTID}"
is_int "${CORES}" && [[ "${CORES}" -ge 1 ]]  || die "Invalid number of cores: ${CORES}"
is_int "${RAM}"   && [[ "${RAM}" -ge 2048 ]] || die "XWiki needs at least 2048 MiB RAM (given: ${RAM})."
is_int "${SWAP}"                             || die "Invalid swap size: ${SWAP}"
is_int "${DISK}"  && [[ "${DISK}" -ge 8 ]]   || die "Please use at least 8 GiB disk (given: ${DISK})."
[[ "${CT_HOSTNAME}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die "Invalid hostname: ${CT_HOSTNAME}"
[[ "${DB}" == "pgsql" || "${DB}" == "mariadb" ]] || die "DB must be 'pgsql' or 'mariadb' (given: ${DB})."
[[ "${XWIKI_CHANNEL}" == "stable" || "${XWIKI_CHANNEL}" == "lts" ]] || die "XWIKI_CHANNEL must be 'stable' or 'lts'."
[[ "${UNPRIVILEGED}" == "0" || "${UNPRIVILEGED}" == "1" ]] || die "UNPRIVILEGED must be 0 or 1."
[[ -n "${STORAGE}" ]] || die "No storage for container disks found. Set STORAGE=..."
[[ -n "${TEMPLATE_STORAGE}" ]] || die "No storage for templates found. Set TEMPLATE_STORAGE=..."
if pct status "${CTID}" >/dev/null 2>&1 || qm status "${CTID}" >/dev/null 2>&1; then
  die "ID ${CTID} is already in use."
fi
if [[ "${IP}" != "dhcp" ]]; then
  [[ "${IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || die "IP must be 'dhcp' or CIDR like 192.168.1.50/24."
fi
if [[ -n "${SSH_KEY_FILE}" && ! -r "${SSH_KEY_FILE}" ]]; then
  die "SSH key file not readable: ${SSH_KEY_FILE}"
fi
if [[ -z "${JAVA_XMX}" ]]; then
  JAVA_XMX=$(( RAM * 60 / 100 ))
fi
is_int "${JAVA_XMX}" || die "Invalid JAVA_XMX: ${JAVA_XMX}"

echo
echo "${C_BOLD}Summary${C_RESET}"
printf '  %-18s %s\n' \
  "Container ID" "${CTID}" "Hostname" "${CT_HOSTNAME}" \
  "CPU / RAM / Swap" "${CORES} cores / ${RAM} MiB / ${SWAP} MiB" \
  "Disk" "${DISK} GiB on ${STORAGE}" \
  "Network" "${BRIDGE}, ${IP}${GATEWAY:+ via ${GATEWAY}}${VLAN:+, VLAN ${VLAN}}" \
  "Unprivileged" "${UNPRIVILEGED}" \
  "Database" "${DB}" "XWiki channel" "${XWIKI_CHANNEL}" "Java heap" "${JAVA_XMX} MiB"
echo
if [[ "${ASSUME_YES}" != "1" ]]; then
  read -r -p "Create the container now? [y/N]: " confirm </dev/tty || true
  [[ "${confirm}" =~ ^[YyJj]$ ]] || die "Cancelled by user."
fi

# ---------------------------------------------------------------------------
# Debian template
# ---------------------------------------------------------------------------
# XWiki 18+ needs Java 21, which is the default JDK of Debian 13 (trixie).
msg_info "Updating the template list"
pveam update >/dev/null || msg_warn "pveam update failed - using cached template list."

TEMPLATE="$(pveam available --section system 2>/dev/null \
  | awk '{print $2}' | grep -E '^debian-13-standard_.*_amd64\.tar\.(zst|xz|gz)$' | sort -V | tail -n1 || true)"
[[ -n "${TEMPLATE}" ]] || die "No Debian 13 template found via 'pveam available'."

if ! pveam list "${TEMPLATE_STORAGE}" 2>/dev/null | grep -q "${TEMPLATE}"; then
  msg_info "Downloading template ${TEMPLATE} to ${TEMPLATE_STORAGE}"
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}" >/dev/null
fi
msg_ok "Template ${TEMPLATE}"

# ---------------------------------------------------------------------------
# Create container
# ---------------------------------------------------------------------------
NET="name=eth0,bridge=${BRIDGE},ip=${IP}"
[[ -n "${GATEWAY}" ]] && NET+=",gw=${GATEWAY}"
[[ -n "${VLAN}" ]]    && NET+=",tag=${VLAN}"

PCT_ARGS=(
  --hostname "${CT_HOSTNAME}"
  --cores "${CORES}"
  --memory "${RAM}"
  --swap "${SWAP}"
  --rootfs "${STORAGE}:${DISK}"
  --net0 "${NET}"
  --ostype debian
  --unprivileged "${UNPRIVILEGED}"
  --features nesting=1
  --onboot 1
  --tags xwiki
  --description "XWiki (${XWIKI_CHANNEL}, Tomcat 10, ${DB}) - created by proxmox-script-xwiki v${SCRIPT_VERSION}"
)
[[ -n "${DNS}" ]]          && PCT_ARGS+=(--nameserver "${DNS}")
[[ -n "${CT_PASSWORD}" ]]  && PCT_ARGS+=(--password "${CT_PASSWORD}")
[[ -n "${SSH_KEY_FILE}" ]] && PCT_ARGS+=(--ssh-public-keys "${SSH_KEY_FILE}")

msg_info "Creating LXC container ${CTID}"
pct create "${CTID}" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_ARGS[@]}" >/dev/null
CT_CREATED=1
msg_ok "Container ${CTID} created"

msg_info "Starting container ${CTID}"
pct start "${CTID}"

msg_info "Waiting for network inside the container"
for _ in $(seq 1 60); do
  if pct exec "${CTID}" -- getent hosts deb.debian.org >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
pct exec "${CTID}" -- getent hosts deb.debian.org >/dev/null 2>&1 \
  || die "Container ${CTID} has no working network/DNS."
msg_ok "Network is up"

# ---------------------------------------------------------------------------
# Run installer inside the container
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo .)"
LOCAL_INSTALLER="${SCRIPT_DIR}/install/xwiki-install.sh"
TMP_INSTALLER="$(mktemp)"
trap 'rm -f "${TMP_INSTALLER}"' EXIT

if [[ -r "${LOCAL_INSTALLER}" ]]; then
  cp "${LOCAL_INSTALLER}" "${TMP_INSTALLER}"
else
  msg_info "Downloading installer from ${REPO_RAW_URL}"
  curl -fsSL "${REPO_RAW_URL}/install/xwiki-install.sh" -o "${TMP_INSTALLER}"
fi

pct push "${CTID}" "${TMP_INSTALLER}" /root/xwiki-install.sh --perms 0755
msg_info "Installing XWiki inside the container (this takes several minutes)"
pct exec "${CTID}" -- env \
  DB="${DB}" XWIKI_CHANNEL="${XWIKI_CHANNEL}" JAVA_XMX="${JAVA_XMX}" \
  bash /root/xwiki-install.sh

CT_IP="$(pct exec "${CTID}" -- hostname -I 2>/dev/null | awk '{print $1}' || true)"
CT_CREATED=0

echo
msg_ok "XWiki container ${CTID} (${CT_HOSTNAME}) is ready."
echo
echo "  Open:  ${C_BOLD}http://${CT_IP:-<container-ip>}:8080/xwiki/${C_RESET}"
echo "  The XWiki Distribution Wizard will guide you through creating the"
echo "  admin account and installing the standard flavor."
echo
echo "  Shell: pct enter ${CTID}"
echo "  Logs:  pct exec ${CTID} -- journalctl -u tomcat10 -f"
echo
