#!/bin/bash
# Script de configuración desde la máquina local hacia la máquina Server

## Aqui va descargar repositorio y descomprimir 

# Cargar variables
source ./vars.sh
start=$(date +%s)
SVIP0=$1  # IP actual del servidor (se pasa como argumento al ejecutar el script)

# ------------------------------------------------------------------
# Parte local
# ------------------------------------------------------------------

echo "[+] Actualizando repositorios localmente..."
echo "$PASSsv1" | sudo -S apt update

echo "[+] Instalando sshpass y ansible..."
echo "$PASSsv1" | sudo -S apt install -y sshpass ansible

# ------------------------------------------------------------------
# Parte remota (Server)
# ------------------------------------------------------------------

echo "[+] Generando configuración de red..."
NETPLAN_CONFIG=$(cat <<EOF_NETPLAN
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - ${SVIP1}/22
      routes:
        - to: default
          via: 192.168.236.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
    enp2s0:
      dhcp4: false
      addresses:
        - ${SVIP2}/24
EOF_NETPLAN
)

echo "[+] Conectando y configurando la máquina Server ($SVIP0)..."

sshpass -p "$PASSsv1" ssh -o StrictHostKeyChecking=no "$USERsv1@$SVIP0" bash << EOF
echo "$PASSsv1" | sudo -S bash -c '
    echo "[+] Cambiando contraseña de root..."
    echo "root:$PASSsv2" | chpasswd

    echo "[+] Cambiando hostname a Server..."
    hostnamectl set-hostname Server

    echo "[+] Habilitando acceso root por SSH..."
    sed -i "s/^#\\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
    systemctl restart ssh

    if [ ! -f /etc/netplan/50-cloud-init.yaml.bkup ]; then
        echo "[+] Haciendo copia de seguridad de Netplan..."
        cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bkup
    else
        echo "[i] Backup de Netplan ya existe, no se sobrescribe."
    fi

    echo "[+] Reescribiendo Netplan..."
    cat > /etc/netplan/50-cloud-init.yaml << 'EONET'
$NETPLAN_CONFIG
EONET

    echo "[+] Aplicando nueva configuración de red en segundo plano..."
    nohup bash -c "sleep 2 && netplan apply" > /dev/null 2>&1 &


    echo "[✔] Configuración aplicada. Cerrando sesión."
    exit
'
EOF

# ------------------------------------------------------------------
# Postconfiguración
# ------------------------------------------------------------------

echo "[✔] Script ejecutado correctamente. La máquina Server ya está configurada."

# Clave pública SSH
if [[ -f ~/.ssh/id_rsa.pub ]]; then
    read -p "[?] Ya existe una clave SSH en ~/.ssh/id_rsa.pub. ¿Deseas sobrescribirla? (s/n): " RESP
    if [[ "$RESP" == "s" || "$RESP" == "S" ]]; then
        echo "[+] Eliminando clave SSH antigua..."
        rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
        echo "[+] Generando nueva clave SSH..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    else
        echo "[i] Se usará la clave SSH existente."
    fi
else
    echo "[+] Generando clave SSH..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

echo "[...] Esperando a que la máquina Server esté disponible en $SVIP1..."
for i in {1..10}; do
    ping -c 1 "$SVIP1" > /dev/null 2>&1 && break
    echo "Esperando... ($SVIP1)"
    sleep 3
done

echo "[+] Copiando clave SSH al root del servidor..."
sshpass -p "$PASSsv2" ssh-copy-id root@"$SVIP1"

for PLAYBOOK in "${PLAYBOOK[@]}"; do
    echo "Ejecutando $PLAYBOOK..."
    ansible-playbook -i "$INVENTORY" "$DIR2/$PLAYBOOK"

done

echo "Creando estructura de carpetas Ansible para $PROYECTO..."

# Crear estructura básica
mkdir -p $PROYECTO/{inventory,roles/samba_ad_dc/{tasks,vars,files}}

# Archivo de inventario
cat > $PROYECTO/inventory/hosts <<EOF
[server]
192.168.237.2 ansible_user=root ansible_ssh_pass=melon ansible_become=true
EOF

# Playbook principal
cat > $PROYECTO/playbook.yml <<EOF
---
- name: Desplegar servidor Samba AD DC
  hosts: server
  become: yes
  roles:
    - samba_ad_dc
EOF

# Variables del rol
cat > $PROYECTO/roles/samba_ad_dc/vars/main.yml <<EOF
hostname: dc
ip_address: 192.168.1.2
dns_forwarder: 8.8.8.8
fqdn: dc.hjm.local
domain_name: hjm.local
realm: HJM.LOCAL
domain: hjm
net_prefix: 192.168.1.0/24
admin_password: usuario1234*
EOF

# Tareas del rol
cat > $PROYECTO/roles/samba_ad_dc/tasks/main.yml <<'EOF'
---
- name: Establecer hostname
  ansible.builtin.hostname:
    name: "{{ hostname }}"

- name: Añadir FQDN a /etc/hosts
  ansible.builtin.lineinfile:
    path: /etc/hosts
    line: "{{ ip_address }} {{ fqdn }} {{ hostname }}"
    create: yes

- name: Desactivar y detener systemd-resolved
  ansible.builtin.systemd:
    name: systemd-resolved
    enabled: no
    state: stopped

- name: Crear /etc/resolv.conf
  ansible.builtin.copy:
    dest: /etc/resolv.conf
    content: |
      nameserver {{ ip_address }}
      nameserver {{ dns_forwarder }}
      search {{ domain_name }}

- name: Verificar si resolv.conf es inmutable
  ansible.builtin.shell: lsattr /etc/resolv.conf | grep '\-i\-'
  register: resolv_conf_attr
  changed_when: false
  failed_when: false

- name: Establecer el atributo inmutable si no está
  ansible.builtin.shell: chattr +i /etc/resolv.conf
  when: resolv_conf_attr.rc != 0

- name: Instalar paquetes necesarios
  ansible.builtin.apt:
    name:
      - acl
      - attr
      - samba
      - samba-dsdb-modules
      - samba-vfs-modules
      - smbclient
      - winbind
      - libpam-winbind
      - libnss-winbind
      - libpam-krb5
      - krb5-config
      - krb5-user
      - dnsutils
      - chrony
      - net-tools
    state: present
    update_cache: yes

- name: Deshabilitar servicios innecesarios
  ansible.builtin.systemd:
    name: "{{ item }}"
    enabled: no
    state: stopped
  loop:
    - smbd
    - nmbd
    - winbind

- name: Habilitar samba-ad-dc
  ansible.builtin.systemd:
    name: samba-ad-dc
    enabled: yes
    masked: no

- name: Backup smb.conf si existe
  ansible.builtin.command: mv /etc/samba/smb.conf /etc/samba/smb.conf.orig
  args:
    removes: /etc/samba/smb.conf

- name: Provisonar dominio Samba
  ansible.builtin.command: >
    samba-tool domain provision
    --realm={{ realm }}
    --domain={{ domain }}
    --server-role=dc
    --dns-backend=SAMBA_INTERNAL
    --adminpass='{{ admin_password }}'
  register: provision_result
  changed_when: "'Administrator password' in provision_result.stdout"

- name: Sustituir krb5.conf
  ansible.builtin.copy:
    remote_src: yes
    src: /var/lib/samba/private/krb5.conf
    dest: /etc/krb5.conf
    force: yes

- name: Iniciar servicio samba-ad-dc
  ansible.builtin.systemd:
    name: samba-ad-dc
    state: started

- name: Crear usuario hjmer en el dominio
  ansible.builtin.command: >
    samba-tool user create hjmer usuario123*
  register: create_user_result
  changed_when: "'Created user' in create_user_result.stdout"

- name: Establecer permisos en ntp_signd
  ansible.builtin.file:
    path: /var/lib/samba/ntp_signd/
    owner: root
    group: _chrony
    mode: '0750'

- name: Configurar chrony
  ansible.builtin.blockinfile:
    path: /etc/chrony/chrony.conf
    block: |
      bindcmdaddress {{ ip_address }}
      allow {{ net_prefix }}
      ntpsigndsocket /var/lib/samba/ntp_signd

- name: Reiniciar y habilitar chronyd
  ansible.builtin.systemd:
    name: chronyd
    enabled: yes
    state: restarted

EOF

echo "[✔] Estructura del proyecto creada correctamente en ./$PROYECTO"
echo " Ejecutando ansible..."
sleep 2
cd $PROYECTO/
ansible-playbook -i inventory/hosts playbook.yml

echo "Ansible terminado"
end=$(date +%s)
runtime=$((end - start))

echo "Tiempo de ejecución: $runtime segundos"
