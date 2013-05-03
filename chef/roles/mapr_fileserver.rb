name "mapr_fileserver"
description "MapR FileServer Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::fileserver]"
)
default_attributes(

)
