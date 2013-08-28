class mapr::webserver 
{
  package { 'mapr-webserver':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }
}
