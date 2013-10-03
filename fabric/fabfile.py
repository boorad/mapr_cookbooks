from fabric.api import *

INSTALL_DIR="/opt/install_mapr"
CHEF_DIR="%s/chef" % INSTALL_DIR

# DEV only
env.hosts = ['i1']
env.user = 'vagrant'
env.password = 'vagrant'


## composite phase tasks
def phase_1():
    install_omnibus_chef()
    make_mapr_install_chef_dir()
    copy_manifest()
    copy_cookbooks()

def phase_2():
    package_install()

def test():
    copy_manifest()
    copy_cookbooks()
    package_install()


## supporting sub-tasks
def install_omnibus_chef():
    sudo("curl -L https://www.opscode.com/chef/install.sh | bash")

def keygen():
    local("ssh-keygen -t rsa -P '' -f ~/.ssh/mapr_rsa")

def make_mapr_install_chef_dir():
    sudo("mkdir -p %s" % CHEF_DIR)
    sudo("chown -R %s:%s %s" % (env.user,env.user,INSTALL_DIR))

def copy_manifest():
    manifest = get_manifest()
    put(manifest, INSTALL_DIR)

def copy_cookbooks():
    put("../chef/*", CHEF_DIR)

def package_install():
    manifest = get_manifest()
    sudo("chef-solo -c %s/solo.rb -j %s/%s" % (CHEF_DIR, INSTALL_DIR, manifest))


## utility functions
def get_manifest():
    return "%s_manifest.json" % env.host_string
