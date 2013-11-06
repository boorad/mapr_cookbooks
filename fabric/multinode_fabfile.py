from fabric.api import *
import manifests

INSTALL_DIR="/opt/install_mapr"
CHEF_DIR="%s/chef" % INSTALL_DIR
COOKBOOK_DIR="%s/cookbooks" % CHEF_DIR
MAPR_PACKAGE_URL="http://package.mapr.com/releases"

PLATFORM = "redhat"

# for DEV
env.hosts = ["i1"]
env.user = 'vagrant'
env.password = 'vagrant'

##
## composite phase tasks
##
def phase_1():
    set_hosts()
#    set_creds()
#    install_omnibus_chef()
    make_mapr_install_chef_dir()
    generate_manifests()
    copy_manifests()
    copy_chef_bits()
#    create_local_repo()

def phase_2():
    package_install()

def test():
    package_install()


##
## supporting sub-tasks
##
def set_hosts():
    env.hosts = manifests.get_hosts()
    env.ips = manifests.get_ips()

#def set_creds():
#    env.user, env.password = manifests.get_creds()

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
    # phase 1 manifest
    manifest = get_phase1_manifest()
    put(manifest, INSTALL_DIR)

def copy_chef_bits():
    put("../chef/cookbooks", CHEF_DIR)
    put("../chef/roles", CHEF_DIR)
    put("../chef/solo.rb", CHEF_DIR)
    # for dev
    local("cd ../chef/cookbooks/mapr && berks install --path ../../dep_cookbooks")
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
    #

def package_install():
    manifest = get_phase1_manifest()
    chef_solo(manifest)


##
## utility functions
##
def get_phase1_manifest():
    return "%s_manifest.json" % env.host_string

def get_repo_manifest():
    return "local_repo.json"

def chef_solo(manifest):
    with cd(CHEF_DIR):
        sudo("chef-solo -c %s/solo.rb -j %s/%s" % (CHEF_DIR, INSTALL_DIR, manifest))
