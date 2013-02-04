name "mapr_nfs"
description "MapR NFS Gateway Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::nfs]"
)
default_attributes(

)
