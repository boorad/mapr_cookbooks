
import json

## api

def generate():
    c = get_json()

    for node in c["mapr"]["nodes"]:
        n = node["host"]
        print "generating manifests for %s" % n
        m = {'run_list' : run_list(node),
             'mapr'    : mapr(c, node)}
        out = open("%s_manifest.json" % n, 'w')
        out.write(json.dumps(m))
        out.close()

def get_hosts():
    c = get_json()
    hosts = []
    for node in c["mapr"]["nodes"]:
        hosts.append(node["host"])
    return hosts

def get_ips():
    c = get_json()
    ips = []
    for node in c["mapr"]["nodes"]:
        ips.append(node["ip"])
    return ips

##
## supporting functions
##

def get_json():
    cluster = open('cluster.json')
    c = json.load(cluster)
    cluster.close()
    return c

def run_list(n):
    ret = []
    for r in n["roles"]:
        ret.append("role[%s]" % r)
    return ret

def mapr(c, n):
    n1 = dict(n)
    del n1["roles"]
    ret = {'version' : c["mapr"]["install"]["version"],
           'node'    : n1,
           'nodes'   : nodes(c),
           'groups'  : groups(c)}
    return ret

def nodes(c):
    ret = []
    for n in c["mapr"]["nodes"]:
        ret.append({'ip' : n["ip"], 'host' : n["host"], 'fqdn' : n["fqdn"]})
    return ret

def groups(c):
    all = []
    cldb = []
    zk = []
    jt = []
    tt = []

    for n in c["mapr"]["nodes"]:
        ip = n["ip"]
        all.append(ip)
        roles = n["roles"]
        if "mapr_control_node" in roles:
            cldb.append(ip)
            zk.append(ip)
            jt.append(ip)
        if "mapr_cldb" in roles:
            cldb.append(ip)
        if "mapr_zookeeper" in roles:
            zk.append(ip)
        if "mapr_jobtracker" in roles:
            jt.append(ip)
        if "mapr_data_node" in roles or "mapr_tasktracker" in roles:
            tt.append(ip)

    return {'all' : all,
            'cldb' : cldb,
            'zk' : zk,
            'jt' : jt,
            'tt' : tt}
