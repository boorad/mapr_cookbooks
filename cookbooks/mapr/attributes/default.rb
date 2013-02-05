default[:ntp][:servers] = ["0.pool.ntp.org", "1.pool.ntp.org"]

default[:hostname] = "nodeX"
default[:fqdn] = "nodeX.cluster.com"
default[:ip] = "1.1.1.1"

default[:mapr][:version] = "2.1.1"
default[:mapr][:repo_url] = "http://package.mapr.com/releases"

default[:mapr][:disks] = ["/dev/sdb","/dev/sdc","/dev/sdd"]
