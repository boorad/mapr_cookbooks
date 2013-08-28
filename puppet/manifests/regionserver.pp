class mapr::regionserver {
  $package_names = [ 'mapr-hbase-regionserver' ]

  package { $package_names:
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }
}