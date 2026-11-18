# Redis Cluster en 3 VMs (Vagrant)

3 VMs Debian, cada una con 2 instancias de Redis (puertos 7000 y 7001) = 6 nodos:
3 masters + 3 réplicas. Cada réplica queda en una VM distinta a la de su master.

| VM | IP | 7000 | 7001 |
|---|---|---|---|
| nodo1 | 192.168.56.11 | master | réplica del master de nodo3 |
| nodo2 | 192.168.56.12 | master | réplica del master de nodo1 |
| nodo3 | 192.168.56.13 | master | réplica del master de nodo2 |

## Requisitos

- Vagrant y VirtualBox
- ≈ 3 GB de RAM libres (1 GB por VM)

## Iniciar

```bash
cp .env.example .env      # edita .env y cambia REDIS_PASS
vagrant up
```

Al terminar, nodo3 (la última VM) crea el cluster solo. Si repites `vagrant provision`, no lo vuelve a crear.

## Comprobar que funciona

Entra a una VM y exporta la clave para no escribirla en cada comando:

```bash
vagrant ssh nodo1
export REDISCLI_AUTH='tu_password'
```

**1. El cluster está sano**
```bash
redis-cli -p 7000 CLUSTER INFO | head -n 3
```
Debe decir `cluster_state:ok` y `cluster_slots_ok:16384`.

**2. Hay 6 nodos, 3 masters y 3 réplicas**
```bash
redis-cli -p 7000 CLUSTER NODES
```
Cada réplica (`slave`) debe apuntar a un master que esté en **otra** VM.
Revisión completa: `redis-cli --cluster check 192.168.56.11:7000` (debe terminar en `[OK] All 16384 slots covered`).

**3. Se puede escribir y leer**
```bash
redis-cli -c -p 7000 SET hola mundo
redis-cli -c -p 7000 GET hola
```
(`-c` sigue las redirecciones entre nodos.)

## Probar un fallo

**Caída de un proceso** (desde nodo1):
```bash
sudo systemctl stop redis-7000
```
Espera ≈ 10 s y mira desde otro nodo: `redis-cli -h 192.168.56.13 -p 7000 CLUSTER NODES`.
Su réplica (192.168.56.12:7001) debe pasar a `master`. Para recuperar:
```bash
sudo systemctl start redis-7000     # vuelve como réplica
```

**Caída de una VM completa** (desde tu máquina, fuera de las VMs):
```bash
vagrant halt nodo2
```
Espera ≈ 15 s y consulta `CLUSTER NODES` desde nodo1: los nodos de nodo2 aparecen como `fail`, la réplica `192.168.56.13:7001` pasa a `master` y `CLUSTER INFO` sigue en `cluster_state:ok`. Para recuperar:
```bash
vagrant up nodo2
```
Para devolver los roles originales, cuando `192.168.56.12:7000` ya esté sincronizado (`INFO replication` → `master_link_status:up`), ejecuta ahí mismo `redis-cli -p 7000 CLUSTER FAILOVER`.

## Comandos útiles

| Qué | Comando |
|---|---|
| Estado de las VMs | `vagrant status` |
| Reaplicar provisión | `vagrant provision` |
| Empezar de cero | `vagrant destroy -f && vagrant up` |
| Logs de una instancia | `tail -f /logs/redis-7000.log` (dentro de la VM) |
| Estado de un servicio | `systemctl status redis-7000` |

## Si algo falla

- **`Define REDIS_PASS`**: falta el archivo `.env` o la variable.
- **El cluster no se creó**: `vagrant provision nodo3` repite solo ese paso. Revisa antes que las 6 instancias respondan (`redis-cli -h 192.168.56.12 -p 7001 PING`).
- **`NOAUTH` o `WRONGPASS`**: la clave del `.env` no coincide con la que usaste al crear las VMs. Si la cambiaste después, haz `vagrant destroy -f && vagrant up`.
