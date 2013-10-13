name "mapr_control_node"
description "MapR Control Node role"
run_list(
  "role[mapr_cldb]",
  "role[mapr_zookeeper]",
  "role[mapr_fileserver]",
  "role[mapr_jobtracker]",
  "role[mapr_webserver]"
)
default_attributes(

)
