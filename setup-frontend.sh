#!/usr/bin/env bash
VARS_FILE="${VARS_FILE:-./vars-opennebula.env}"
if [[ ! -f "$VARS_FILE" ]]; then echo "Vars file non trouvé: $VARS_FILE"; exit 1; fi
# shellcheck disable=SC1090
source "$VARS_FILE"

# Sécu bash
if [[ "${SET_STRICT_BASH}" == "true" ]]; then set -euo pipefail; fi

# Helpers
log(){ printf "\n[+] %s\n" "$*"; }
run(){ echo "+ $*"; eval "$*"; }

# Prep APT
if [[ "${NON_INTERACTIVE}" == "true" ]]; then export DEBIAN_FRONTEND=noninteractive; fi

log "Vérif OS"
if ! grep -q "${OS_CODENAME}" /etc/os-release; then
  echo "Ce script cible ${OS_CODENAME}. Vérifie ta distro."; exit 1
fi

log "Config hostname et TZ"
run "sudo hostnamectl set-hostname ${FRONTEND_HOSTNAME}"
run "sudo timedatectl set-timezone ${TIMEZONE}"

log "MAJ systeme"
run "sudo apt update"
run "sudo apt upgrade -y"
run "sudo apt autoremove -y"

log "Install prérequis KVM/libvirt/bridge"
run "sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils ssh ${EXTRA_FRONTEND_PACKAGES}"
run "sudo systemctl enable --now libvirtd"

if [[ "${CONFIGURE_NETPLAN_BRIDGE}" == "true" ]]; then
  log "Configurer Netplan bridge ${BRIDGE_NAME} (⚠️ peut cut la session ssh)"
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
      addresses: [${BRIDGE_CIDR}]
      gateway4: ${GATEWAY_IP}
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF'"
  run "sudo netplan apply"
fi

log "Ajouter dépôt OpenNebula ${ONE_REPO_MAJOR} (${ONE_REPO_CHANNEL})"
APT_FILE="/etc/apt/sources.list.d/opennebula.list"
run "echo \"deb [trusted=yes] https://downloads.opennebula.io/repo/${ONE_REPO_MAJOR}/Ubuntu/${OS_CODENAME} ${ONE_REPO_CHANNEL} ${ONE_REPO_NAME}\" | sudo tee ${APT_FILE} >/dev/null"
run "sudo apt update"

log "Install Front (core + Sunstone + FireEdge)"
run "sudo apt install -y opennebula opennebula-sunstone opennebula-fireedge"

log "Active services OpenNebula"
run "sudo systemctl enable opennebula opennebula-sunstone opennebula-fireedge"
run "sudo systemctl start opennebula opennebula-sunstone opennebula-fireedge"

log "Infos Sunstone"
echo "URL:  http://${FRONTEND_IP}:${SUNSTONE_PORT}/"
echo "User: oneadmin"
echo "Pass: (voir) sudo cat /var/lib/one/.one/one_auth"

log "Préparer SSH pour l’utilisateur oneadmin (clé ${SSH_KEY_TYPE})"
if [[ "${CREATE_SSH_KEY_IF_MISSING}" == "true" ]]; then
  run "sudo -u oneadmin bash -lc 'test -f ~/.ssh/id_${SSH_KEY_TYPE} || ssh-keygen -t ${SSH_KEY_TYPE} -N \"\" -f ~/.ssh/id_${SSH_KEY_TYPE}'"
fi

log "Bootstrap SSH vers le node (${SSH_TARGET_USER}@${NODE_IP})"
if [[ -n "${NODE_SSH_PASSWORD}" ]]; then
  run "sudo apt install -y sshpass"
  run "sudo -u oneadmin bash -lc 'sshpass -p \"${NODE_SSH_PASSWORD}\" ssh-copy-id -o StrictHostKeyChecking=no ${SSH_TARGET_USER}@${NODE_IP}'"
else
  echo ">>> Si demandé, entre le mot de passe de ${SSH_TARGET_USER}@${NODE_IP} pour copier la clé."
  run "sudo -u oneadmin bash -lc 'ssh-copy-id -o StrictHostKeyChecking=no ${SSH_TARGET_USER}@${NODE_IP}'"
fi

log "Test SSH sans pass"
run "sudo -u oneadmin bash -lc 'ssh -o BatchMode=yes ${SSH_TARGET_USER}@${NODE_IP} true'"

log "Créer l’hôte OpenNebula pour node KVM"
run "sudo -u oneadmin onehost create ${NODE_HOSTNAME} -i kvm -v kvm -n dummy"

if [[ "${ADD_FRONTEND_AS_COMPUTE}" == "true" ]]; then
  log "Ajoute le Frontend comme hote compute (hybride)"
  run "sudo -u oneadmin onehost create ${FRONTEND_HOSTNAME} -i kvm -v kvm -n dummy"
fi

log "Vérifie l’état des hôtes"
run "sudo -u oneadmin onehost list || true"

log "It's DONE =D — Et voilà Eze =D connecte-toi à Sunstone: http://${FRONTEND_IP}:${SUNSTONE_PORT}/"
