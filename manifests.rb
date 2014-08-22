module MapRManifests
  def groups(nodes)
    all = []
    cldb = []
    zk = []
    jt = []
    tt = []
    
    # puts "We have #{nodes.length} nodes"

    all = nodes
    nodes.each do |n|
      # puts "Working on node:"
      # debugger;
      # puts "It's a TaskTracker node" if ( n['roles'].include?('mapr_data_node') || n['roles'].include?('mapr_tasktracker') )

      if n['roles'].include?('mapr_control_node')
        cldb.push n
        zk.push n
        jt.push n
      end
      cldb.push n if n['roles'].include?('mapr_cldb')
      zk.push n   if n['roles'].include?('mapr_zookeeper')
      jt.push n   if n['roles'].include?('mapr_jobtracker')
      tt.push n   if ( n['roles'].include?('mapr_data_node') || n['roles'].include?('mapr_tasktracker') )
    end

    return  {  'all'  => all,
               'cldb' => cldb,
               'zk'   => zk,
               'jt'   => jt,
               'tt'   => tt
            }
  end
  module_function :groups
  
end