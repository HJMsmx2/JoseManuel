#!/bin/bash
# Script de configuración desde la máquina local hacia la máquina Server

# Variables
USERsv1="usuario"
PASSsv1="usuario"
PASSsv2="melon"
HOST_IP0=$1         # IP actual de la Server
HOST_IP=$2          # IP estática que se aplicará

# ------------------------------------------------------------------
# Parte local
# ------------------------------------------------------------------

echo "[+] Actualizando repositorios localmente..."
echo "$PASSsv1" | sudo -S apt update
#echo "$PASSsv1" | sudo -S apt upgrade -y

echo "[+] Instalando sshpass en la máquina local..."
echo "$PASSsv1" | sudo -S apt install sshpass -y

# ------------------------------------------------------------------
# Parte remota (Server)
# ------------------------------------------------------------------

echo "[+] Conectando y configurando la máquina Server..."

sshpass -p "$PASSsv1" ssh -o StrictHostKeyChecking=no "$USERsv1@$HOST_IP0" bash << EOF
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
    cat > /etc/netplan/50-cloud-init.yaml << EONET
network:
    ethernets:
        enp1s0:
            dhcp4: false
            addresses:
              - $HOST_IP/22
            routes:
              - to: default
                via: 192.168.236.1
            nameservers:
              addresses: [192.168.236.1]
    version: 2
EONET

    echo "[+] Aplicando nueva configuración de red en segundo plano..."
    nohup bash -c "sleep 2 && netplan apply" > /dev/null 2>&1 &

    echo "[✔] Configuración aplicada. La IP va a cambiar. Cerrando sesión."
    exit
'
EOF

echo "[✔] Script ejecutado correctamente. La máquina Server ya está configurada."

# ------------------------------------------------------------------
# Comprobación de la conectividad y conexión al root del servidor.
# ------------------------------------------------------------------
    
echo "[...] Esperando a que la máquina Server esté disponible en su nueva IP..."

for i in {1..10}; do
    ping -c 1 "$HOST_IP" > /dev/null 2>&1 && break
    echo "Esperando... ($i)"
    sleep 3
done

echo "[+] Comprobando conexión SSH como root..."
sshpass -p "$PASSsv2" ssh -o StrictHostKeyChecking=no root@"$HOST_IP"
