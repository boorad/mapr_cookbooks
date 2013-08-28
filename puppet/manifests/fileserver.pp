class mapr::fileserver
{
  package { 'mapr-fileserver':
  	ensure => installed,
  	require => File['/etc/yum.repos.d/maprtech.repo'],
  }

  file { '/tmp/disks.txt':
    alias  => 'disks',
    ensure => present,
    mode   => '0644',
    source => 'puppet:///modules/mapr/disks.txt',
  }

  file { '/opt/mapr/hadoop/hadoop-0.20.2/conf/core-site.xml':
    ensure => present,
    owner  => 'mapr',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/mapr/core-site.xml',
  }
}
