from fabric.api import *

# DEV only
#env.hosts = ['mapr@i1','mapr@i2','mapr@i3']
env.hosts = ['i1']
env.user = 'vagrant'
env.password = 'vagrant'

def install_omnibus_chef():
    sudo("curl -L https://www.opscode.com/chef/install.sh | bash")

def keygen():
    local("ssh-keygen -t rsa -P '' -f ~/.ssh/mapr_rsa")

def make_mapr_install_dir():
    run("mkdir -p ~/mapr_install")

def copy_manifest():
    put(env.host_string + "_manifest.json", "mapr_install")
