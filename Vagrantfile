# -*- mode: ruby -*-
# vi: set ft=ruby :
$LOAD_PATH.unshift File.dirname(__FILE__)

require 'fileutils'
require 'json'
require 'manifests'

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.require_version ">= 1.6.0"

MAPR_BOOTSTRAP_PATH = File.join(File.dirname(__FILE__), "install_mapr")
MAPR_TARBALL = File.join(File.dirname(__FILE__), "install_mapr.tar.gz")
CONFIG = File.join(File.dirname(__FILE__), "vagrant-config.rb")

# Defaults for config options defined in CONFIG
$num_instances = 1
#$enable_serial_logging = false
$vb_gui = false
$vb_memory = 1024
$vb_cpus = 1
$mapr_cluster_attributes = JSON.load(File.open(File.join(MAPR_BOOTSTRAP_PATH, 'fabric', 'cluster.json')))

# Attempt to apply the deprecated environment variable NUM_INSTANCES to
# $num_instances while allowing config.rb to override it
if ENV["NUM_INSTANCES"].to_i > 0 && ENV["NUM_INSTANCES"]
  $num_instances = ENV["NUM_INSTANCES"].to_i
end

if File.exist?(CONFIG)
  require CONFIG
end


Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # All Vagrant configuration is done here. The most common configuration
  # options are documented and commented below. For a complete reference,
  # please see the online documentation at vagrantup.com.

  # Set the version of chef to install using the vagrant-omnibus plugin
  config.omnibus.chef_version = :latest

  # Every Vagrant virtual environment requires a box to build off of.
  # If this value is a shorthand to a box in Vagrant Cloud then 
  # config.vm.box_url doesn't need to be specified.
  config.vm.box = "chef/ubuntu-14.04"

  # The url from where the 'config.vm.box' box will be fetched if it
  # is not a Vagrant Cloud box and if it doesn't already exist on the 
  # user's system.
  config.vm.box_url = "http://opscode-vm-bento.s3.amazonaws.com/vagrant/virtualbox/opscode_ubuntu-13.10_chef-provisionerless.box"

  config.vm.provider :vmware_fusion do |vb, override|
    override.vm.box_url = "http://opscode-vm-bento.s3.amazonaws.com/vagrant/vmware/opscode_ubuntu-13.10_chef-provisionerless.box"
  end

  (1..$num_instances).each do |i|
    config.vm.define vm_name = "mapr-%02d" % i do |config|
      config.vm.hostname = vm_name

      if $enable_serial_logging
        logdir = File.join(File.dirname(__FILE__), "log")
        FileUtils.mkdir_p(logdir)

        serialFile = File.join(logdir, "%s-serial.txt" % vm_name)
        FileUtils.touch(serialFile)

        config.vm.provider :vmware_fusion do |v, override|
          v.vmx["serial0.present"] = "TRUE"
          v.vmx["serial0.fileType"] = "file"
          v.vmx["serial0.fileName"] = serialFile
          v.vmx["serial0.tryNoRxLoss"] = "FALSE"
        end

        config.vm.provider :virtualbox do |vb, override|
          vb.customize ["modifyvm", :id, "--uart1", "0x3F8", "4"]
          vb.customize ["modifyvm", :id, "--uartmode1", serialFile]
        end
      end

      # if $expose_docker_tcp
      #   config.vm.network "forwarded_port", guest: 2375, host: ($expose_docker_tcp + i - 1), auto_correct: true
      # end

      config.vm.provider :vmware_fusion do |vb|
        vb.gui = $vb_gui
      end

      config.vm.provider :virtualbox do |vb|
        vb.gui = $vb_gui
        vb.memory = $vb_memory
        vb.cpus = $vb_cpus
      end

      ip = "172.17.9.#{i+100}"
      config.vm.network :private_network, ip: ip

      # Assign this VM to a host-only network IP, allowing you to access it
      # via the IP. Host-only networks can talk to the host machine as well as
      # any other machines on the same network, but cannot be accessed (through this
      # network interface) by any external networks.
      config.vm.network :private_network, type: "dhcp"

      # Create a forwarded port mapping which allows access to a specific port
      # within the machine from a port on the host machine. In the example below,
      # accessing "localhost:8080" will access port 80 on the guest machine.

      # Share an additional folder to the guest VM. The first argument is
      # the path on the host to the actual folder. The second argument is
      # the path on the guest to mount the folder. And the optional third
      # argument is a set of non-required options.
      # config.vm.synced_folder "../data", "/vagrant_data"
      config.vm.synced_folder "install_mapr", "/home/vagrant/install_mapr", :nfs => true, :mount_options => ['nolock,vers=3,udp']

      # Provider-specific configuration so you can fine-tune various
      # backing providers for Vagrant. These expose provider-specific options.
      # Example for VirtualBox:
      #
      # config.vm.provider :virtualbox do |vb|
      #   # Don't boot with headless mode
      #   vb.gui = true
      #
      #   # Use VBoxManage to customize the VM. For example to change memory:
      #   vb.customize ["modifyvm", :id, "--memory", "1024"]
      # end
      #
      # View the documentation for the provider you're using for more
      # information on available options.

      # The path to the Berksfile to use with Vagrant Berkshelf
      # config.berkshelf.berksfile_path = "./Berksfile"

      # Enabling the Berkshelf plugin. To enable this globally, add this configuration
      # option to your ~/.vagrant.d/Vagrantfile file
      # config.berkshelf.enabled = true

      # An array of symbols representing groups of cookbook described in the Vagrantfile
      # to exclusively install and copy to Vagrant's shelf.
      # config.berkshelf.only = []

      # An array of symbols representing groups of cookbook described in the Vagrantfile
      # to skip installing and copying to Vagrant's shelf.
      # config.berkshelf.except = []

      config.vm.provision :chef_solo do |chef|
        chef.cookbooks_path = [ File.join(MAPR_BOOTSTRAP_PATH, 'chef', 'cookbooks') ]
        chef.roles_path = [ File.join(MAPR_BOOTSTRAP_PATH, 'chef', 'roles') ]
        
        chef.json = {
          mysql: {
            server_root_password: 'rootpass',
            server_debian_password: 'debpass',
            server_repl_password: 'replpass'
          }
        }

        # Add nodes to attributes hash
        $mapr_cluster_attributes['mapr']['nodes'].push( { "ip" => "172.17.9.#{i+100}", "host" => "mapr-%02d" % i, "fqdn" => "mapr-%02d.dev.vagrantbox.com" % i, "disks" => [ "/dev/mapper/vagrant--vg-root" ], "roles" => [ "mapr_data_node" ] } )

        # Make first node a control node
        $mapr_cluster_attributes['mapr']['nodes'][0]['roles'].unshift('mapr_control_node') unless $mapr_cluster_attributes['mapr']['nodes'][0]['roles'].include?('mapr_control_node')

        # Generate a group listing of the nodes
        $mapr_cluster_attributes['mapr']['groups'] = MapRManifests.groups($mapr_cluster_attributes['mapr']['nodes'])

        ## This definitely needs to be fixed to be [D.R.Y.](https://en.wikipedia.org/wiki/Don't_repeat_yourself)!
        ## The mapr::clush recipe expects a hash of role-grouped hosts in the MapR cluster categorized by services they run
        ## So the code in the recipe expects us to generate this and put it in attributes.
        ## The orchestration code for fabric in 'manifests.py' handles generating this, but we don't have fabric usable in 
        ## the Vagrantfile yet, so we must re-implement it in 'manifests.rb'.  This should be D.R.Y.-ed up, and maybe rethought/refactored
        # require 'pp'
        # pp $mapr_cluster_attributes

        chef.json.merge!( $mapr_cluster_attributes )
        # pp chef.json

        # Testing
        # chef.run_list = [
        #     "recipe[mapr::env]"
        # ]
        chef.run_list = $mapr_cluster_attributes['mapr']['nodes'][i-1]['roles'].collect {|r| "role[#{r}]" }
      end

      # config.vm.provision :fabric do |fabric|
      #   fabric.fabfile_path = "./fabfile.py"
      #   fabric.tasks ["test"]
      # end

      # if File.exist?(MAPR_BOOTSTRAP_PATH)
      #   if $install_vector == 'tarball'
      #     config.vm.provision :file, :source => "#{MAPR_TARBALL}", :destination => "/tmp/"
      #     config.vm.provision :shell, :inline => "tar -C /tmp/ -xf /tmp/#{MAPR_TARBALL} && cd /tmp/install_mapr && ./install", :privileged => true
      #   else
      #     config.vm.provision :shell, :inline => "cd /home/vagrant/install_mapr && ./install", :privileged => true
      #   end
      # end
    end
  end
end
