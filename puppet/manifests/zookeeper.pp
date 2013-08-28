class mapr::zookeeper 
{
  package { 'mapr-zookeeper':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }
}
