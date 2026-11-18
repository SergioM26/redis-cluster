#!/usr/bin/env bash
# Instala Redis y deja listas N instancias en modo cluster dentro de ESTA VM.
# Lo ejecuta el Vagrantfile:  provision_node.sh <IP> <puerto> [puerto ...]
# Requiere la variable REDIS_PASS.

set -euo pipefail

IP="$1"; shift
PORTS=("$@")
: "${REDIS_PASS:?Define REDIS_PASS}"

SUBNET="192.168.56.0/24"
CONF_DIR=/etc/redis/cluster
DATA_BASE=/data1
LOG_DIR=/logs

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y redis-server ufw

# El servicio por defecto no se usa: cada instancia tiene su propia unit
systemctl disable --now redis-server || true
REDIS_BIN="$(command -v redis-server)"

# Recomendado por Redis para BGSAVE / reescritura de AOF
sysctl -w vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' > /etc/sysctl.d/99-redis.conf

mkdir -p "$CONF_DIR" "$LOG_DIR"
chown redis:redis "$CONF_DIR" "$LOG_DIR"

for p in "${PORTS[@]}"; do
  echo "==> Instancia $p"
  mkdir -p "$DATA_BASE/$p"
  chown redis:redis "$DATA_BASE/$p"

  cat > "$CONF_DIR/redis-$p.conf" <<CONF
port $p
bind 0.0.0.0
protected-mode yes
daemonize no
supervised systemd

# Cluster
cluster-enabled yes
cluster-config-file nodes-$p.conf
cluster-node-timeout 5000
cluster-announce-ip $IP

# Persistencia
dir $DATA_BASE/$p
appendonly yes

# Logs
logfile $LOG_DIR/redis-$p.log

# Autenticacion
requirepass $REDIS_PASS
masterauth $REDIS_PASS
CONF
  chown redis:redis "$CONF_DIR/redis-$p.conf"
  chmod 640 "$CONF_DIR/redis-$p.conf"

  # Restart=no: para las pruebas de fallo, un kill -9 no debe revivir solo.
  # Cámbialo a on-failure si quieres que systemd lo reinicie.
  cat > "/etc/systemd/system/redis-$p.service" <<UNIT
[Unit]
Description=Redis Cluster node $p
After=network.target

[Service]
Type=notify
User=redis
Group=redis
ExecStart=$REDIS_BIN $CONF_DIR/redis-$p.conf --supervised systemd
Restart=no
LimitNOFILE=65535
ProtectSystem=off
ProtectHome=off

[Install]
WantedBy=multi-user.target
UNIT
done

# Firewall: SSH (Vagrant) + puertos de Redis y de bus de cluster, solo desde la subred
ufw allow 22/tcp
for p in "${PORTS[@]}"; do
  ufw allow from "$SUBNET" to any port "$p" proto tcp
  ufw allow from "$SUBNET" to any port "$((p + 10000))" proto tcp
done
ufw --force enable

systemctl daemon-reload
for p in "${PORTS[@]}"; do
  systemctl enable --now "redis-$p"
done

echo "==> Instancias activas en $IP:"
for p in "${PORTS[@]}"; do
  printf "  %s -> " "$p"; systemctl is-active "redis-$p"
done
