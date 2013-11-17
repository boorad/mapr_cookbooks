import os.path
from fabric.api import *
import manifests

INSTALL_DIR="/opt/install_mapr"
CHEF_DIR="%s/chef" % INSTALL_DIR
COOKBOOK_DIR="%s/cookbooks" % CHEF_DIR
MAPR_PACKAGE_URL="http://package.mapr.com/releases"

PLATFORM = "redhat"

env.use_ssh_config=True

##
## composite phase tasks
##
def phase_1():
    install_omnibus_chef()
    make_mapr_install_chef_dir()
    generate_manifests()
    copy_manifests()
    copy_chef_bits()
#    create_local_repo()

def phase_2():
    package_install()

def phase_3():
    configure()

def phase_4():
    start_services()

def test():
    pass


##
## supporting sub-tasks
##

def install_omnibus_chef():
    sudo("curl -L https://www.opscode.com/chef/install.sh | bash")

def keygen():
    local("ssh-keygen -t rsa -P '' -f ~/.ssh/mapr_rsa")

def make_mapr_install_chef_dir():
    sudo("mkdir -p %s" % CHEF_DIR)
    sudo("chown -R %s:%s %s" % (env.user,env.user,INSTALL_DIR))

def generate_manifests():
    manifests.generate()

def copy_manifests():
    manifest = get_node_manifest()
    put(manifest, INSTALL_DIR)

def copy_chef_bits():
    put("../chef/cookbooks", CHEF_DIR)
    put("../chef/roles", CHEF_DIR)
    put("../chef/solo.rb", CHEF_DIR)
    # for dev
    if os.path.isfile("../DEV"):
        local("cd ../chef/cookbooks/mapr && berks install "
              "--path ../../dep_cookbooks")
        put("../chef/dep_cookbooks/*", COOKBOOK_DIR)

def download_mapr_packages():
    dest = "repo/"
    # core
    ver = manifests.get_version()
    url = "%s/v%s/%s/mapr-v%sGA.rpm.tgz" % (MAPR_PACKAGE_URL, ver, platform, ver)
    print url
#    local("wget -r --relative -nd -P %s %s" % (dest, url))
    # ecosystem
    url = "%s/ecosystem/%s/" % (MAPR_PACKAGE_URL, platform)
    print url
#    local("wget -r -nd -P %s -A *.tgz %s" % (dest, url))

def create_local_repo():
    download_mapr_packages()

def package_install():
    chef_solo()

def configure():
    chef_solo("role[mapr_configure]")

def start_services():
    pass

##
## utility functions
##
def get_node_manifest():
    return "%s_manifest.json" % env.host_string

def get_repo_manifest():
    return "local_repo.json"

def chef_solo(runlist=None):
    manifest = get_node_manifest()
    rl = ""
    if runlist:
        rl = " -o %s" % runlist

    with cd(CHEF_DIR):
        sudo("chef-solo -c %s/solo.rb -j %s/%s%s"
             % (CHEF_DIR, INSTALL_DIR, manifest, rl))
