class mapr::metrics 
{
  package { 'mapr-metrics':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }
}
