# Redis Cluster en 3 VMs (2 instancias por VM: 7000 = master, 7001 = réplica).
#
# Uso:
#   cp .env.example .env     (y cambia REDIS_PASS)
#   vagrant up
#
# nodo3 es la última VM en levantarse y ejecuta create_cluster.sh,
# que forma el cluster cuando las 6 instancias ya responden.
# (Con libvirt, usa: vagrant up --no-parallel)

# Carga .env (líneas CLAVE=valor) si existe. Una variable ya exportada tiene prioridad.
env_file = File.join(__dir__, ".env")
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    next if key.nil? || value.nil?
    ENV[key.strip] ||= value.strip.gsub(/\A["']|["']\z/, "")
  end
end

REDIS_PASS = ENV.fetch("REDIS_PASS") { abort "Define REDIS_PASS: copia .env.example a .env o exporta la variable" }

NODES = {
  "nodo1" => "192.168.56.11",
  "nodo2" => "192.168.56.12",
  "nodo3" => "192.168.56.13",
}

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"

  NODES.each do |name, ip|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: ip

      node.vm.provider "virtualbox" do |vb|
        vb.name   = "redis-#{name}"
        vb.memory = 1024
        vb.cpus   = 1
      end

      # 1) Instalar Redis y levantar las 2 instancias de esta VM
      node.vm.provision "shell",
        path: "provision_node.sh",
        args: [ip, "7000", "7001"],
        env: { "REDIS_PASS" => REDIS_PASS }

      # 2) Solo en la última VM: crear el cluster
      if name == "nodo3"
        node.vm.provision "shell",
          path: "create_cluster.sh",
          env: { "REDIS_PASS" => REDIS_PASS }
      end
    end
  end
end
