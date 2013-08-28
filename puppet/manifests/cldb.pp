class mapr::cldb 
{
  package { 'mapr-cldb':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }
}
