#!/bin/bash
# Nombre del proyecto
PROYECTO="ADDC-HJM"
enp1s0="192.168.237.2"

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

- name: Eliminar /etc/resolv.conf
  ansible.builtin.file:
    path: /etc/resolv.conf
    state: absent

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

# VERIFICACIONES

- name: Verificar A record hjm.local
  ansible.builtin.command: host -t A {{ domain_name }}

- name: Verificar A record FQDN
  ansible.builtin.command: host -t A {{ fqdn }}

- name: Verificar SRV Kerberos
  ansible.builtin.command: host -t SRV _kerberos._udp.{{ domain_name }}

- name: Verificar SRV LDAP
  ansible.builtin.command: host -t SRV _ldap._tcp.{{ domain_name }}

- name: Comprobar recursos Samba
  ansible.builtin.command: smbclient -L {{ domain_name }} -N

- name: Autenticación Kerberos con kinit
  ansible.builtin.shell: echo '{{ admin_password }}' | kinit administrator@{{ realm }}

- name: Listar credenciales Kerberos
  ansible.builtin.command: klist

- name: Comprobar acceso a netlogon
  ansible.builtin.command: >
    smbclient //localhost/netlogon -U administrator%'{{ admin_password }}'
- name: Verificar configuración de samba
  ansible.builtin.command: testparm -s

- name: Mostrar nivel de dominio
  ansible.builtin.command: samba-tool domain level show
EOF

echo "[✔] Estructura del proyecto creada correctamente en ./$PROYECTO"
echo " Ejecutando ansible..."
sleep 2
cd $PROYECTO/
ansible-playbook -i inventory/hosts playbook.yml

echo "Ansible terminado"
