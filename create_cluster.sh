#!/usr/bin/env bash
# Forma el cluster con topología en anillo y es idempotente:
#   nodo1: M(7000) + R(7001, réplica del master de nodo3)
#   nodo2: M(7000) + R(7001, réplica del master de nodo1)
#   nodo3: M(7000) + R(7001, réplica del master de nodo2)
# Cada réplica queda en una VM distinta a la de su master.
#
# Corre en nodo3 (última VM). Requiere REDIS_PASS.
# Versión corta (reparto automático): sustituye los pasos 3 y 4 por
#   redis-cli --cluster create $M1 $R1 $M2 $R2 $M3 $R3 --cluster-replicas 1 --cluster-yes

set -euo pipefail
: "${REDIS_PASS:?Define REDIS_PASS}"
export REDISCLI_AUTH="$REDIS_PASS"

H1=192.168.56.11; H2=192.168.56.12; H3=192.168.56.13
M1=$H1:7000; M2=$H2:7000; M3=$H3:7000      # masters
R1=$H1:7001; R2=$H2:7001; R3=$H3:7001      # réplicas
ALL="$M1 $M2 $M3 $R1 $R2 $R3"

info() { redis-cli -h "$1" -p "$2" CLUSTER INFO | tr -d '\r' | awk -F: -v k="$3" '$1==k{print $2}'; }

echo "==> 1. Esperando a las 6 instancias"
for n in $ALL; do
  until redis-cli -h "${n%:*}" -p "${n#*:}" PING 2>/dev/null | grep -q PONG; do sleep 2; done
done

echo "==> 2. ¿Ya existe el cluster?"
if [ "$(info $H1 7000 cluster_state)" = "ok" ]; then
  echo "Cluster ya creado, no se hace nada."; exit 0
fi

echo "==> 3. Creando los 3 masters"
redis-cli --cluster create $M1 $M2 $M3 --cluster-replicas 0 --cluster-yes

for i in $(seq 1 30); do
  [ "$(info $H1 7000 cluster_state)" = "ok" ] && [ "$(info $H1 7000 cluster_known_nodes)" = "3" ] && break
  sleep 2
done

ID1=$(redis-cli -h $H1 -p 7000 CLUSTER MYID | tr -d '\r')
ID2=$(redis-cli -h $H2 -p 7000 CLUSTER MYID | tr -d '\r')
ID3=$(redis-cli -h $H3 -p 7000 CLUSTER MYID | tr -d '\r')

echo "==> 4. Añadiendo las réplicas (anillo)"
redis-cli --cluster add-node $R1 $M1 --cluster-slave --cluster-master-id "$ID3"
sleep 2
redis-cli --cluster add-node $R2 $M1 --cluster-slave --cluster-master-id "$ID1"
sleep 2
redis-cli --cluster add-node $R3 $M1 --cluster-slave --cluster-master-id "$ID2"

echo "==> 5. Esperando a que el cluster converja"
for i in $(seq 1 30); do
  [ "$(info $H1 7000 cluster_known_nodes)" = "6" ] && [ "$(info $H1 7000 cluster_state)" = "ok" ] && break
  sleep 2
done

echo "==> 6. Verificación"
redis-cli --cluster check $M1
redis-cli -h $H1 -p 7000 CLUSTER NODES
