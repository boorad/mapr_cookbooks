name "mapr_configure"
description "MapR Configure Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::disable_services]",
  "recipe[mapr::configure]",
  "recipe[mapr::disksetup]",
  "recipe[mapr::enable_services]"
)
default_attributes(

)
