# Service account for mapr service
# The mapr-warden service handles starting the actual mapr services so the
# classes for each service should be ran first while the warden class is run
# last
class mapr
{

#FIXME: add  stage => pre

  user { 'mapr':
    uid        => '583',
    gid        => '583',
    comment    => 'Service account for mapr',
    home       => '/usr/home/mapr',
    shell      => '/bin/bash',
    managehome => true,
  }

  group { 'mapr':
    gid => '583'
  }

  realize Group[hadoop]
  realize Group[mapred]
  realize User[mapred]

  file { '/etc/yum.repos.d/maprtech.repo':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => 'puppet:///modules/mapr/maprtech.repo',
  }

############################################################
#Place holder for future ssh key for mapr user.            #
############################################################
#  ssh_authorized_key { 'mapr@mapr-prod-001':
#    user => 'mapr',
#    type => 'rsa',
#    key  => '',
#  }
}
