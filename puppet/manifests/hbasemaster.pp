class mapr::hbasemaster 
{
  package { 'mapr-hbase-master':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }
}
