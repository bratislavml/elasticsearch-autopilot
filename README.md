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
978920c36fdd        mterron/consul-autopilot          es_consul_3
1022dc1c12ee        mterron/consul-autopilot          es_consul_2
ac7adb374728        mterron/elasticsearch-autopilot   es_elasticsearch_client_1
a2d946cc77fa        mterron/elasticsearch-autopilot   es_elasticsearch_data_1
a40d64cfccf2        mterron/elasticsearch-autopilot   es_elasticsearch_master_1
56c248bbe1af        mterron/consul-autopilot          es_consul_1
e7962af4d6b2        mterron/elasticsearch-autopilot   es_elasticsearch_1
```

##### Check Consul cluster status
```bash
$ docker exec -t es_consul_1 consul members
Node          Address          Status  Type    Build  Protocol  DC
1022dc1c12ee  172.20.0.7:8301  alive   server  0.6.4  2         demodc
56c248bbe1af  172.20.0.2:8301  alive   server  0.6.4  2         demodc
978920c36fdd  172.20.0.8:8301  alive   server  0.6.4  2         demodc
```

##### Let's check the cluster health.
```bash
$ docker exec -t es_elasticsearch_1 sh -c 'curl "http://$(hostname -i):9200/_cluster/health?pretty=true"'
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

##### Let's get some more details on the cluster:
The composition logs are redirected to Logstash and stored in Elasticsearch
