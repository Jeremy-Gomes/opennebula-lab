#!/usr/bin/env bash
# OpenNebula – Node KVM setup (Ubuntu 22.04)
VARS_FILE="${VARS_FILE:-./vars-opennebula.env}"
if [[ ! -f "$VARS_FILE" ]]; then echo "Vars file non trouvé: $VARS_FILE"; exit 1; fi
# shellcheck disable=SC1090
source "$VARS_FILE"

if [[ "${SET_STRICT_BASH}" == "true" ]]; then set -euo pipefail; fi

log(){ printf "\n[+] %s\n" "$*"; }
run(){ echo "+ $*"; eval "$*"; }

if [[ "${NON_INTERACTIVE}" == "true" ]]; then export DEBIAN_FRONTEND=noninteractive; fi

log "Vérif OS"
if ! grep -q "${OS_CODENAME}" /etc/os-release; then
  echo "Ce script cible ${OS_CODENAME}. Vérifie ta distro."; exit 1
fi

log "Config hostname t TZ"
run "sudo hostnamectl set-hostname ${NODE_HOSTNAME}"
run "sudo timedatectl set-timezone ${TIMEZONE}"

log "MAJ système"
run "sudo apt update"
run "sudo apt upgrade -y"
run "sudo apt autoremove -y"

log "Install KVM/libvirt et utils"
run "sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils ssh ${EXTRA_NODE_PACKAGES}"
run "sudo systemctl enable --now libvirtd"

if [[ "${CONFIGURE_NETPLAN_BRIDGE}" == "true" ]]; then
  log "Config Netplan bridge ${BRIDGE_NAME} (peut cut le ssh)"
  NETPLAN="/etc/netplan/01-${BRIDGE_NAME}.yaml"
  run "sudo bash -c 'cat > ${NETPLAN} <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${PHYS_IFACE}:
      dhcp4: no
  bridges:
    ${BRIDGE_NAME}:
      interfaces: [${PHYS_IFACE}]
      addresses: [${NODE_IP}/24]
      gateway4: ${GATEWAY_IP}
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF'"
  run "sudo netplan apply"
fi

log "Ajout dépot OpenNebula ${ONE_REPO_MAJOR}"
APT_FILE="/etc/apt/sources.list.d/opennebula.list"
run "echo \"deb [trusted=yes] https://downloads.opennebula.io/repo/${ONE_REPO_MAJOR}/Ubuntu/${OS_CODENAME} ${ONE_REPO_CHANNEL} ${ONE_REPO_NAME}\" | sudo tee ${APT_FILE} >/dev/null"
run "sudo apt update"

log "Install role Node KVM"
run "sudo apt install -y opennebula-node-kvm"

log "Vérifie que l’user ${SSH_TARGET_USER} existe"
if ! id -u "${SSH_TARGET_USER}" >/dev/null 2>&1; then
  log "Créer ${SSH_TARGET_USER} et groupes requis"
  run "sudo useradd -m -s /bin/bash ${SSH_TARGET_USER}"
  run "sudo usermod -aG libvirt ${SSH_TARGET_USER}"
  run "echo \"${SSH_TARGET_USER} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/99-${SSH_TARGET_USER} >/dev/null"
fi

log "Autorise libvirt pour ${SSH_TARGET_USER}"
run "sudo usermod -aG libvirt,kvm ${SSH_TARGET_USER}"

log "Dossiers datastores"
run "sudo mkdir -p ${DATASTORE_DIR}"
run "sudo chown -R ${SSH_TARGET_USER}:${SSH_TARGET_USER} ${DATASTORE_DIR}"

log "It's DONE =D — Et voilà Eze =D Node prêt à être ajouté depuis le Frontend (${FRONTEND_HOSTNAME})"
