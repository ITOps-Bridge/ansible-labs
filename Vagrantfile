Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus = 2
  end

  controller_pubkey_path = "/vagrant/ssh/id_rsa.pub"

  config.vm.define "controller" do |c|
    c.vm.hostname = "controller"
    c.vm.network "private_network", ip: "192.168.56.110"
    c.vm.provision "shell", inline: <<-SHELL
      set -e
      sudo apt-get update -y
      sudo apt-get install -y python3-pip
      python3 -m pip install --upgrade pip
      pip install ansible passlib
      sudo apt-get install -y  git sshpass
      mkdir -p /vagrant/ssh
      if [ ! -f /vagrant/ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -N "" -f /vagrant/ssh/id_rsa
        chmod 600 /vagrant/ssh/id_rsa
      fi
      echo "[OK] Clé SSH générée dans /vagrant/ssh/"
    SHELL
  end

  def provision_node(vmconfig, ip, hostname, controller_pubkey_path)
    vmconfig.vm.hostname = hostname
    vmconfig.vm.network "private_network", ip: ip
    vmconfig.vm.provision "shell", inline: <<-SHELL
      set -e
      sudo apt-get update -y
      sudo apt-get install -y python3
      if ! id ansible >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash ansible
        echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-ansible
      fi
      sudo mkdir -p /home/ansible/.ssh
      if [ -f #{controller_pubkey_path} ]; then
        sudo cp #{controller_pubkey_path} /home/ansible/.ssh/authorized_keys
        sudo chown -R ansible:ansible /home/ansible/.ssh
        sudo chmod 700 /home/ansible/.ssh
        sudo chmod 600 /home/ansible/.ssh/authorized_keys
      else
        echo "ATTENTION: clé publique introuvable (#{controller_pubkey_path}). Lance d’abord 'vagrant up controller'."
      fi
    SHELL
  end

  config.vm.define "node1" do |n1|
    provision_node(n1, "192.168.56.111", "node1", controller_pubkey_path)
  end

  config.vm.define "node2" do |n2|
    provision_node(n2, "192.168.56.112", "node2", controller_pubkey_path)
  end
end