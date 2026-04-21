Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "airgap-bundler"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "16384"
    vb.cpus = 8
    vb.name = "airgap-vm"

    # Enable Host I/O Cache for better disk performance
    vb.customize ["storagectl", :id, "--name", "SATA Controller", "--hostiocache", "on"]

    # Disable linked clone for better disk performance
    vb.linked_clone = false

    vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
    vb.customize ["modifyvm", :id, "--vram", "128"]
    vb.customize ["modifyvm", :id, "--accelerate-3d", "on"]

    # Performance optimizations
    vb.customize ["modifyvm", :id, "--nested-paging", "on"]

    # Remove CPU cap - let VM use full CPU
    vb.customize ["modifyvm", :id, "--cpuexecutioncap", "100"]

    # Enable I/O APIC for better I/O performance
    vb.customize ["modifyvm", :id, "--ioapic", "on"]

    # Enable PAE/NX for hardware virtualization features
    vb.customize ["modifyvm", :id, "--pae", "on"]

    # Enable large pages for better memory performance
    vb.customize ["modifyvm", :id, "--large-pages", "on"]

    # Disable audio (not needed for headless)
    vb.customize ["modifyvm", :id, "--audio", "none"]
  end

  # Set disk size to 75GB
  config.vm.disk :disk, size: "75GB", primary: true

  config.vm.network "private_network", ip: "192.168.56.10", type: "virtio"

  # Mount bundles folder via rsync (only .tar.gz files)
config.vm.synced_folder "bundles", "/bundles",
  type: "rsync",
  rsync__exclude: [".vagrant/", "genesis-*.tar.gz"],
  rsync__auto: true

  config.vm.provision "shell", path: "scripts/bootstrap-vm.sh"

  # Resize disk to use full space
  config.vm.provision "shell", inline: <<-'SHELL'
    lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
    resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
  SHELL

  config.vm.provision "shell", inline: <<-SHELL
    echo "=== Applying Firewall Rules to Block Internet ==="

    # Install UFW
    apt-get install -y ufw

    # Default: deny outgoing
    ufw default deny outgoing

    # Allow localhost/loopback
    ufw allow out on lo
    ufw allow in on lo

    # Allow Docker bridge network
    ufw allow out on docker0
    ufw allow in on docker0

    # Allow local network (host communication)
    ufw allow out on eth0 to 192.168.56.0/24

    # Allow internal cluster traffic
    ufw allow out on eth0 to 10.0.0.0/8

    # Allow SSH from anywhere (vagrant port forwarding uses NAT)
    ufw allow in 22/tcp

    # Enable firewall
    echo "y" | ufw enable

    echo "=== Firewall configured: internet blocked, SSH allowed ==="
    ufw status verbose
  SHELL

  config.ssh.insert_key = false
end