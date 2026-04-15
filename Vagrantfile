Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "airgap-bundler"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
    vb.cpus = 2
    vb.name = "airgap-vm"
  end

  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.synced_folder "bundles", "/bundles",
    type: "rsync",
    create: true

  config.vm.provision "shell", path: "scripts/bootstrap-vm.sh"

  config.ssh.insert_key = false
end