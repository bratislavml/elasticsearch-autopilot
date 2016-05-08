Autopilot Pattern Elasticsearch
==========

[Elasticsearch](https://www.elastic.co/products) designed for automated operation using the [Autopilot Pattern](http://autopilotpattern.io/).

### Discovery with ContainerPilot
Cloud deployments can't take advantage of multicast over the software-defined networks available from AWS, GCE, or Joyent's Triton. Although a separate plugin could be developed to run discovery, in this case we're going to take advantage of a fairly typical production topology for Elasticsearch -- master-only nodes.

When a data node starts, it will use [ContainerPilot](https://github.com/joyent/containerpilot) to query Consul and find a master node to bootstrap unicast zen discovery. We write this to the node configuration file on each start, so if the bootstrap node dies we can still safely reboot data nodes and join them to whatever master is available.

Launch a cluster with a single master-only node, a single data-only node, a single client node and a master/data node.

```bash
$ docker-compose -p es up -d
Pulling elasticsearch_master (mterron/elasticsearch-autopilot:latest)...
latest: Pulling from mterron/elasticsearch-autopilot
...
Status: Downloaded newer image for mterron/elasticsearch-autopilot:latest
Creating es_consul_1...
Creating es_elasticsearch_master_1...
Creating es_elasticsearch_1...
Creating es_data_1...
```

##### Scale up the Consul cluster to 3 nodes to have quorum.
```bash
$ docker-compose -p es scale consul=3
Creating and starting es_consul_2 ... done
Creating and starting es_consul_3 ... done

$ docker ps --format 'table {{ .ID }}\t{{ .Image }}\t{{ .Names }}'
CONTAINER ID        IMAGE                             NAMES
7d9cde11f6c1        mterron/consul-autopilot          es_consul_3
dbcc619b2906        mterron/consul-autopilot          es_consul_2
5b5bf3ee6c73        mterron/elasticsearch-autopilot   es_elasticsearch_client_1
b8627b48f874        mterron/elasticsearch-autopilot   es_elasticsearch_data_1
0530c223a745        mterron/elasticsearch-autopilot   es_elasticsearch_master_1
902e9f9790e0        mterron/elasticsearch-autopilot   es_elasticsearch_1
154dd9e196f1        mterron/consul-autopilot          es_consul_1
```

##### Let's check the cluster health.
```bash
$docker exec -t es_elasticsearch_1 sh -c 'curl "http://$(hostname -i):9200/_cluster/health?pretty=true"'
{
  "cluster_name" : "demo-autopilot",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 4,
  "number_of_data_nodes" : 2,
  "active_primary_shards" : 0,
  "active_shards" : 0,
  "relocating_shards" : 0,
  "initializing_shards" : 0,
  "unassigned_shards" : 0,
  "delayed_unassigned_shards" : 0,
  "number_of_pending_tasks" : 0,
  "number_of_in_flight_fetch" : 0,
  "task_max_waiting_in_queue_millis" : 0,
  "active_shards_percent_as_number" : 100.0
}
```

##### Lets get some more details on the cluster:
```bash
$ docker exec -t es_elasticsearch_1 sh -c 'curl "http://$(hostname -i):9200/_cluster/state?pretty=true"' 
{
  "cluster_name" : "demo-autopilot",
  "version" : 2,
  "state_uuid" : "PFRBCE-0SLynni9T1oKrAg",
  "master_node" : "Zr3rdszPQ9OP_10QV1AStw",
  "blocks" : { },
  "nodes" : {
    "Zr3rdszPQ9OP_10QV1AStw" : {
      "name" : "0530c223a745",
      "transport_address" : "172.20.0.4:9300",
      "attributes" : {
        "data" : "false",
        "master" : "true"
      }
    },
    "bcGzkrmcTeKulwnVcwXrDQ" : {
      "name" : "902e9f9790e0",
      "transport_address" : "172.20.0.3:9300",
      "attributes" : {
        "master" : "true"
      }
    },
    "ns1h5o7MRLyWotIc12fZvQ" : {
      "name" : "5b5bf3ee6c73",
      "transport_address" : "172.20.0.6:9300",
      "attributes" : {
        "data" : "false",
        "master" : "false"
      }
    },
    "k6e1KRvdTGaADVteBy0JyA" : {
      "name" : "b8627b48f874",
      "transport_address" : "172.20.0.5:9300",
      "attributes" : {
        "master" : "false"
      }
    }
  },
  "metadata" : {
    "cluster_uuid" : "qw4kCL3rSv-6pwBbIy-8bQ",
    "templates" : { },
    "indices" : { }
  },
  "routing_table" : {
    "indices" : { }
  },
  "routing_nodes" : {
    "unassigned" : [ ],
    "nodes" : {
      "k6e1KRvdTGaADVteBy0JyA" : [ ],
      "bcGzkrmcTeKulwnVcwXrDQ" : [ ]
    }
  }
}
```
