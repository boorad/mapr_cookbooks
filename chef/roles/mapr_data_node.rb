name "mapr_data_node"
description "MapR Data Node role"
run_list(
  "role[mapr_fileserver]",
  "role[mapr_nfs]",
  "role[mapr_tasktracker]"
)
default_attributes(

)
