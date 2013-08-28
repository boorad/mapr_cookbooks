class mapr::jobtracker 
{
  package { 'mapr-jobtracker':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }

  file { '/opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml':
    ensure => present,
    owner  => 'mapr',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/mapr/mapred-site.xml',
  }
}
