class mapr::nfs 
{
  $package_names = ['mapr-nfs']
  $excluded_services = ['nfs' ]

  package { $package_names:
  	ensure => installed,
    require => File['/etc/yum.repos.d/maprtech.repo'],
  }

  # mapr nfs cannot be ran alongside linux nfs so we have to ensure nfs is
  # stopped see:
  # http://www.mapr.com/doc/display/MapR/Configuring+the+Cluster
  # for more information
  service { $excluded_services:
  	ensure => stopped,
    enable => false
  }
}
