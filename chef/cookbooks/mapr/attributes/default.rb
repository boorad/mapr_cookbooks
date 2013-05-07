default[:mapr][:uid] = 2222
default[:mapr][:gid] = 2222
default[:mapr][:user] = "mapr"
default[:mapr][:group] = "mapr"

default[:ntp][:servers] = ["0.pool.ntp.org", "1.pool.ntp.org"]

default[:mapr][:host] = "nodeX"
default[:mapr][:fqdn] = "nodeX.cluster.com"
default[:mapr][:ip] = "1.1.1.1"


default[:mapr][:home] = "/opt/mapr"
default[:mapr][:clustername] = "my.cluster.com"
default[:mapr][:version] = "2.1.2"
default[:mapr][:repo_url] = "http://package.mapr.com/releases"

default[:mapr][:disks] = ["/dev/sdb","/dev/sdc","/dev/sdd"]
