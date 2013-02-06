maintainer       "MapR Technologies"
maintainer_email "banderson@maprtech.com"
license          "Apache 2.0"
description      "Installs/Configures a MapR Hadoop Cluster"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.1.0"

%w{ centos redhat suse ubuntu }.each do |os|
  supports os
end

depends 'hostsfile'
depends 'hostname'
depends 'apt'
depends 'yum'
