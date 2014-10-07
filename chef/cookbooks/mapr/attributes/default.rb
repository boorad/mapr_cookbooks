default[:mapr][:uid] = 2222
default[:mapr][:gid] = 2222
default[:mapr][:user] = "mapr"
default[:mapr][:group] = "mapr"

default[:ntp][:servers] = ["0.pool.ntp.org", "1.pool.ntp.org"]

default[:mapr][:node][:host] = "nodeX"
default[:mapr][:node][:fqdn] = "nodeX.cluster.com"
default[:mapr][:node][:ip] = "1.1.1.1"


default[:mapr][:home] = "/opt/mapr"
default[:mapr][:clustername] = "my.cluster.com"
default[:mapr][:version] = "3.0.2"
default[:mapr][:repo_url] = "http://package.mapr.com/releases"
default[:mapr][:repo_key_url] = "http://package.mapr.com/releases/pub/gnugpg.key"
# Workaround for "WARNING: The following packages cannot be authenticated!" error
default[:mapr][:pkg_opts] = "--force-yes" if platform_family?('debian')

default[:mapr][:node][:disks] = ["/dev/sdb","/dev/sdc","/dev/sdd"]

# TODO: move each port into its corresponding service recipe.
default[:mapr][:ports] = [
                          7222,
                          7220,
                          7221,
                          60000,
                          9083,
                          9001,
                          50030,
                          389,
                          636,
                          5660,
                          2049,
                          9997,
                          9998,
                          11000,
                          111,
                          25,
                          22,
                          50060,
                          8443,
                          8080,
                          5181,
                          2888,
                          3888
                         ]

default[:mapr][:mapr_subnets] = ""
