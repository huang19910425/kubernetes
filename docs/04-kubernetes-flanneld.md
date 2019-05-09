# Kubernetes集群搭建之CNI-Flanneld部署篇

> Flannel是CoreOS提供用于解决Dokcer集群跨主机通讯的覆盖网络工具。它的主要思路是：预先留出一个网段，每个主机使用其中一部分，然后每个容器被分配不同的ip；让所有的容器认为大家在同一个直连的网络，底层通过UDP/VxLAN等进行报文的封装和转发。

## 架构介绍

Flannel默认使用8285端口作为UDP封装报文的端口，VxLan使用8472端口。

K8s的有很多CNI(网络网络接口)组件，比如Flannel、Calico，我司目前使用的是Flannel，稳定性还可以。所以我这里先只介绍Flannel，Calico后续有机会会分享。
etcd和docker部署在前两篇文章已经结束，这里就不过多展开了。

## Flanneld部署(master节点和node节点都需要安装flanneld)

由于flanneld需要依赖etcd来保证集群IP分配不冲突的问题，所以首先要在etcd中设置 flannel节点所使用的IP段。

```
[root@master01 ~]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" set /coreos.com/network/config '{ "Network": "172.17.0.0/16", "Backend": {"Type": "vxlan"}}'
{ "Network": "172.17.0.0/16", "Backend": {"Type": "vxlan"}}

```

> 注： flanneld默认的Backend 类型是udp   这里改成vxlan 性能要比udp好一些

1. 解压flanneld

```
[root@master01 ~]# cd kubernetes/package/
[root@master01 package]# tar xf flannel-v0.11.0-linux-amd64.tar.gz
[root@master01 package]# cp -rp flanneld mk-docker-opts.sh /usr/bin/
[root@master01 package]# scp -rp flanneld mk-docker-opts.sh root@master02:/usr/bin/ 
[root@master01 package]# scp -rp flanneld mk-docker-opts.sh root@master03:/usr/bin/   
[root@master01 package]# scp -rp flanneld mk-docker-opts.sh root@node01:/usr/bin/ 
[root@master01 package]# scp -rp flanneld mk-docker-opts.sh root@node02:/usr/bin/   
[root@master01 package]# rm -rf flanneld mk-docker-opts.sh README.md 
```

2. 配置flanneld

```
[root@master01 package]# more /etc/kubernetes/flanneld 
FLANNEL_OPTIONS="--etcd-endpoints=https://192.168.1.163:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 -etcd-cafile=/etc/etcd/ssl/ca.pem -et
cd-certfile=/etc/etcd/ssl/server.pem -etcd-keyfile=/etc/etcd/ssl/server-key.pem -etcd-prefix=/coreos.com/network"
[root@master01 package]# scp -rp /etc/kubernetes/flanneld root@master02:/etc/kubernetes/
[root@master01 package]# scp -rp /etc/kubernetes/flanneld root@master03:/etc/kubernetes/
[root@master01 package]# scp -rp /etc/kubernetes/flanneld root@node01:/etc/kubernetes/
[root@master01 package]# scp -rp /etc/kubernetes/flanneld root@node02:/etc/kubernetes/
```

3. 配置flanneld启动文件

```
[root@master01 package]# more /usr/lib/systemd/system/flanneld.service 
[Unit]
Description=Flanneld overlay address etcd agent
After=network-online.target network.target
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/etc/kubernetes/flanneld
ExecStart=/usr/bin/flanneld --ip-masq $FLANNEL_OPTIONS
ExecStartPost=/usr/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/subnet.env
Restart=on-failure

[Install]
WantedBy=multi-user.target
[root@master01 package]# scp -rp /usr/lib/systemd/system/flanneld.service root@master02:/usr/lib/systemd/system/
[root@master01 package]# scp -rp /usr/lib/systemd/system/flanneld.service root@master03:/usr/lib/systemd/system/
[root@master01 package]# scp -rp /usr/lib/systemd/system/flanneld.service root@node01:/usr/lib/systemd/system/
[root@master01 package]# scp -rp /usr/lib/systemd/system/flanneld.service root@node02:/usr/lib/systemd/system/
```

> 注: mk-docker-opts.sh 脚本将分配给 flanneld 的 Pod 子网网段信息写入 /run/flannel/docker 文件，后续 docker 启动时 使用这个文件中的环境变量配置 docker0 网桥； flanneld 使用系统缺省路由所在的接口与其它节点通信，对于有多个网络接口（如内网和公网）的节点，可以用 -iface 参数指定通信接口; flanneld 运行时需要 root 权限；

4. 配置Docker启动参数

在各个节点安装好以后最后要更改Docker的启动参数，使其能够使用flannel进行IP分配，以及网络通讯。
修改docker的启动参数，并使其启动后使用由flannel生成的配置参数，修改如下:
```
[root@master01 package]# more /usr/lib/systemd/system/docker.service 
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
BindsTo=containerd.service
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket


[Service]
Type=notify
EnvironmentFile=/run/flannel/subnet.env
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --graph /data/app/docker $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
[root@master01 package]# scp -rp /usr/lib/systemd/system/docker.service root@master02:/usr/lib/systemd/system/   
[root@master01 package]# scp -rp /usr/lib/systemd/system/docker.service root@master03:/usr/lib/systemd/system/ 
[root@master01 package]# scp -rp /usr/lib/systemd/system/docker.service root@node01:/usr/lib/systemd/system/ 
[root@master01 package]# scp -rp /usr/lib/systemd/system/docker.service root@node02:/usr/lib/systemd/system/ 
```

5. 启动服务

相继启动各节点的服务 注意启动flannel再重启docker 才会覆盖docker0网桥
```
[root@master01 package]# systemctl daemon-reload
[root@master01 package]# systemctl start flanneld
[root@master01 package]# systemctl enable flanneld
Created symlink from /etc/systemd/system/multi-user.target.wants/flanneld.service to /usr/lib/systemd/system/flanneld.service.
[root@master01 package]# systemctl restart docker
[root@master01 package]# systemctl status docker
● docker.service - Docker Application Container Engine
   Loaded: loaded (/usr/lib/systemd/system/docker.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2019-05-08 11:18:00 CST; 4s ago
     Docs: https://docs.docker.com
 Main PID: 34566 (dockerd)
    Tasks: 14
   Memory: 34.5M
   CGroup: /system.slice/docker.service
           └─34566 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --graph /data/app/docker --bip=172.17.63.1/24 --ip-masq=false --mtu=1450

May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.072108624+08:00" level=info msg="pickfirstBalancer: HandleSubConnStateChange: 0xc4201891e0, READY" module=grpc
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.072094048+08:00" level=info msg="pickfirstBalancer: HandleSubConnStateChange: 0xc4208c4140, READY" module=grpc
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.093264268+08:00" level=info msg="[graphdriver] using prior storage driver: overlay2"
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.100527751+08:00" level=info msg="Graph migration to content-addressability took 0.00 seconds"
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.104172224+08:00" level=info msg="Loading containers: start."
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.759378310+08:00" level=info msg="Loading containers: done."
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.897760977+08:00" level=info msg="Docker daemon" commit=e8ff056 graphdriver(s)=overlay2 version=18.09.5
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.898175562+08:00" level=info msg="Daemon has completed initialization"
May 08 11:18:00 master01 dockerd[34566]: time="2019-05-08T11:18:00.927801029+08:00" level=info msg="API listen on /var/run/docker.sock"
May 08 11:18:00 master01 systemd[1]: Started Docker Application Container Engine.
```

> flannel服务启动时主要做了以下几步的工作： 从etcd中获取network的配置信息 划分subnet，并在etcd中进行注册 将子网信息记录到/run/flannel/subnet.env中，以保证各个节点的flanneld IP不会重复分配

6. 验证服务

```
# master01 
[root@master01 package]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:0c:29:5d:e0:2b brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.161/24 brd 192.168.1.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:06:b8:94:d5 brd ff:ff:ff:ff:ff:ff
    inet 172.17.63.1/24 brd 172.17.63.255 scope global docker0
       valid_lft forever preferred_lft forever
4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default 
    link/ether 5e:5e:6c:db:36:bc brd ff:ff:ff:ff:ff:ff
    inet 172.17.63.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever

# master02
[root@master02 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:0c:29:50:92:94 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.162/24 brd 192.168.1.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:ce:f2:cc:e0 brd ff:ff:ff:ff:ff:ff
    inet 172.17.5.1/24 brd 172.17.5.255 scope global docker0
       valid_lft forever preferred_lft forever
4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default 
    link/ether 62:bd:fa:a8:4f:92 brd ff:ff:ff:ff:ff:ff
    inet 172.17.5.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever

# master03
[root@master03 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:0c:29:ca:54:0b brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.163/24 brd 192.168.1.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:c3:dc:24:23 brd ff:ff:ff:ff:ff:ff
    inet 172.17.44.1/24 brd 172.17.44.255 scope global docker0
       valid_lft forever preferred_lft forever
4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default 
    link/ether 72:48:41:28:23:61 brd ff:ff:ff:ff:ff:ff
    inet 172.17.44.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever

# node01
[root@node01 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:0c:29:30:f3:4f brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.164/24 brd 192.168.1.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:ca:61:23:db brd ff:ff:ff:ff:ff:ff
    inet 172.17.30.1/24 brd 172.17.30.255 scope global docker0
       valid_lft forever preferred_lft forever
4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default 
    link/ether aa:b7:9f:37:43:f1 brd ff:ff:ff:ff:ff:ff
    inet 172.17.30.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever

# node02
[root@node02 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:0c:29:12:81:84 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.165/24 brd 192.168.1.255 scope global noprefixroute eth0
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:11:bd:b9:8a brd ff:ff:ff:ff:ff:ff
    inet 172.17.40.1/24 brd 172.17.40.255 scope global docker0
       valid_lft forever preferred_lft forever
4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default 
    link/ether be:b8:2a:21:0a:b6 brd ff:ff:ff:ff:ff:ff
    inet 172.17.40.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever
```

需要确保docker0和flanneld在同一个网段
测试不同节点互通，在master-01上ping另外几个节点的docker0 ip

```
# master01
[root@master01 package]# ping 172.17.5.1
PING 172.17.5.1 (172.17.5.1) 56(84) bytes of data.
64 bytes from 172.17.5.1: icmp_seq=1 ttl=64 time=2.02 ms
64 bytes from 172.17.5.1: icmp_seq=2 ttl=64 time=1.39 ms
--- 172.17.5.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3005ms
rtt min/avg/max/mdev = 1.159/1.457/2.027/0.342 ms

[root@master01 package]# ping 172.17.44.1
PING 172.17.44.1 (172.17.44.1) 56(84) bytes of data.
64 bytes from 172.17.44.1: icmp_seq=1 ttl=64 time=2.19 ms
64 bytes from 172.17.44.1: icmp_seq=2 ttl=64 time=0.941 ms
--- 172.17.44.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3006ms
rtt min/avg/max/mdev = 0.916/1.280/2.196/0.532 ms

[root@master01 kubernetes]# ping 172.17.30.1
PING 172.17.30.1 (172.17.30.1) 56(84) bytes of data.
64 bytes from 172.17.30.1: icmp_seq=1 ttl=64 time=1.89 ms
64 bytes from 172.17.30.1: icmp_seq=2 ttl=64 time=1.21 ms
--- 172.17.30.1 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1000ms
rtt min/avg/max/mdev = 1.215/1.556/1.898/0.343 ms

[root@master01 kubernetes]# ping 172.17.40.1
PING 172.17.40.1 (172.17.40.1) 56(84) bytes of data.
64 bytes from 172.17.40.1: icmp_seq=1 ttl=64 time=1.49 ms
64 bytes from 172.17.40.1: icmp_seq=2 ttl=64 time=1.03 ms
--- 172.17.40.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2004ms
rtt min/avg/max/mdev = 1.038/1.231/1.495/0.195 ms
```

如果能通说明Flannel部署成功。如果不通检查下日志：journalctl -u flannel或 tailf /var/log/messages
最后我们来看下etcd中保存的网段信息

```
[root@master01 kubernetes]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" ls /coreos.com/network/subnets
/coreos.com/network/subnets/172.17.63.0-24
/coreos.com/network/subnets/172.17.5.0-24
/coreos.com/network/subnets/172.17.44.0-24
/coreos.com/network/subnets/172.17.30.0-24
/coreos.com/network/subnets/172.17.40.0-24

[root@master01 package]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" get /coreos.com/network/subnets/172.17.63.0-24
{"PublicIP":"192.168.1.161","BackendType":"vxlan","BackendData":{"VtepMAC":"5e:5e:6c:db:36:bc"}}
[root@master01 package]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" get /coreos.com/network/subnets/172.17.5.0-24
{"PublicIP":"192.168.1.162","BackendType":"vxlan","BackendData":{"VtepMAC":"62:bd:fa:a8:4f:92"}}
[root@master01 package]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" get /coreos.com/network/subnets/172.17.44.0-24
{"PublicIP":"192.168.1.163","BackendType":"vxlan","BackendData":{"VtepMAC":"72:48:41:28:23:61"}}
[root@master01 kubernetes]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" get /coreos.com/network/subnets/172.17.30.0-24
{"PublicIP":"192.168.1.164","BackendType":"vxlan","BackendData":{"VtepMAC":"aa:b7:9f:37:43:f1"}}
[root@master01 kubernetes]# etcdctl --ca-file=/etc/etcd/ssl/ca.pem --cert-file=/etc/etcd/ssl/server.pem --key-file=/etc/etcd/ssl/server-key.pem --endpoints="https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379" get /coreos.com/network/subnets/172.17.40.0-24
{"PublicIP":"192.168.1.165","BackendType":"vxlan","BackendData":{"VtepMAC":"be:b8:2a:21:0a:b6"}}
```

好了，到这一步我们就完成了flanneld的部署