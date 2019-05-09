# Kubernetes集群搭建之Master配置篇

今天终于到正题了~~

## 生成kubernets证书与私钥

1. 制作kubernetes ca证书

```
[root@master01 ssl]# cd /etc/kubernetes/ssl/
[root@master01 ssl]# more ca-config.json 
{
	"signing": {
		"default": {
			"expiry": "87600h"
		},
		"profiles": {
			"kubernetes": {
				"expiry": "87600h",
				"usages": [
					"signing",
					"key encipherment",
					"server auth",
					"client auth"
				]
			}
		}
	}
}
[root@master01 ssl]# more ca-csr.json 
{
	"CN": "kubernetes",
	"key": {
		"algo": "rsa",
		"size": 2048
	},
	"names": [{
		"C": "CN",
		"L": "Hangzhou",
		"ST": "Hangzhou",
		"O": "k8s",
		"OU": "System"
	}]
}

[root@master01 ssl]# cfssl gencert -initca ca-csr.json | cfssljson -bare ca
2019/05/08 13:19:10 [INFO] generating a new CA key and certificate from CSR
2019/05/08 13:19:10 [INFO] generate received request
2019/05/08 13:19:10 [INFO] received CSR
2019/05/08 13:19:10 [INFO] generating key: rsa-2048
2019/05/08 13:19:11 [INFO] encoded CSR
2019/05/08 13:19:11 [INFO] signed certificate with serial number 147401034229152171546499775955471539912895698031

```

2. 制作api证书

```
[root@master01 ssl]# more server-csr.json 
{
	"CN": "kubernetes",
	"hosts": [
		"10.254.0.1",
		"127.0.0.1",
		"192.168.1.161",
		"192.168.1.162",
		"192.168.1.163",
		"kubernetes",
		"kubernetes.default",
		"kubernetes.default.svc",
		"kubernetes.default.svc.cluster",
		"kubernetes.default.svc.cluster.local"
	],
	"key": {
		"algo": "rsa",
		"size": 2048
	},
	"names": [{
		"C": "CN",
		"L": "Hangzhou",
		"ST": "Hangzhou",
		"O": "k8s",
		"OU": "System"
	}]
}

[root@master01 ssl]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server
2019/05/08 13:20:02 [INFO] generate received request
2019/05/08 13:20:02 [INFO] received CSR
2019/05/08 13:20:02 [INFO] generating key: rsa-2048
2019/05/08 13:20:04 [INFO] encoded CSR
2019/05/08 13:20:04 [INFO] signed certificate with serial number 693885960055508636520218162106019513270156783837
2019/05/08 13:20:04 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").

```

3. 制作kube-proxy证书

```
[root@master01 ssl]# more kube-proxy-csr.json 
{
	"CN": "system:kube-proxy",
	"hosts": [],
	"key": {
		"algo": "rsa",
		"size": 2048
	},
	"names": [{
		"C": "CN",
		"L": "Hangzhou",
		"ST": "Hangzhou",
		"O": "k8s",
		"OU": "System"
	}]
}

[root@master01 ssl]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
2019/05/08 13:20:48 [INFO] generate received request
2019/05/08 13:20:48 [INFO] received CSR
2019/05/08 13:20:48 [INFO] generating key: rsa-2048
2019/05/08 13:20:49 [INFO] encoded CSR
2019/05/08 13:20:49 [INFO] signed certificate with serial number 436580994158310755934897688241103948627383384707
2019/05/08 13:20:49 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").

[root@master01 ssl]# ll
总用量 52
-rw-r--r-- 1 root root  249 5月   8 13:16 ca-config.json
-rw-r--r-- 1 root root 1005 5月   8 13:19 ca.csr
-rw-r--r-- 1 root root  183 5月   8 13:16 ca-csr.json
-rw------- 1 root root 1679 5月   8 13:19 ca-key.pem
-rw-r--r-- 1 root root 1363 5月   8 13:19 ca.pem
-rw-r--r-- 1 root root 1013 5月   8 13:20 kube-proxy.csr
-rw-r--r-- 1 root root  205 5月   8 13:16 kube-proxy-csr.json
-rw------- 1 root root 1675 5月   8 13:20 kube-proxy-key.pem
-rw-r--r-- 1 root root 1407 5月   8 13:20 kube-proxy.pem
-rw-r--r-- 1 root root 1261 5月   8 13:20 server.csr
-rw-r--r-- 1 root root  444 5月   8 13:16 server-csr.json
-rw------- 1 root root 1679 5月   8 13:20 server-key.pem
-rw-r--r-- 1 root root 1635 5月   8 13:20 server.pem
```

## 部署Master组件

* kubernetes master 节点运行如下组件： kube-apiserver kube-scheduler kube-controller-manager. 
* kube-scheduler 和 kube-controller-manager 可以以集群模式运行，通过 leader 选举产生一个工作进程，其它进程处于阻塞模式，master三节点高可用模式下可用

### 部署api-server

1. 解压缩

```
[root@master01 package]# tar xf kubernetes-server-linux-amd64.tar.gz 
[root@master01 package]# cd kubernetes/server/bin/
[root@master01 bin]# cp kube-scheduler kube-apiserver kube-controller-manager kubectl kube-proxy kubelet /usr/bin/
[root@master01 bin]# scp -rp kube-scheduler kube-apiserver kube-controller-manager kubectl kube-proxy kubelet root@master02:/usr/bin/
[root@master01 bin]# scp -rp kube-scheduler kube-apiserver kube-controller-manager kubectl kube-proxy kubelet root@master03:/usr/bin/
```

2. 生成api-server所需要的TLS Token

```
[root@master01 kubernetes]# pwd
/etc/kubernetes
[root@master01 kubernetes]# head -c 16 /dev/urandom | od -An -t x | tr -d ' '
e3d7a665fd20d6ea217e33c34f122bcf 
[root@master01 kubernetes]# more token.csv 
e3d7a665fd20d6ea217e33c34f122bcf,kubelet-bootstrap,10001,"system:kubelet-bootstrap"
```

3. 创建api-server配置文件

```
[root@master01 kubernetes]# more /etc/kubernetes/kube-apiserver 
KUBE_APISERVER_OPTS="--logtostderr=true \
--v=4 \
--etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 \
--bind-address=192.168.1.161 \
--secure-port=6443 \
--advertise-address=192.168.1.161 \
--allow-privileged=true \
--service-cluster-ip-range=10.254.0.0/16 \
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \
--authorization-mode=RBAC,Node \
--enable-bootstrap-token-auth \
--token-auth-file=/etc/kubernetes/token.csv \
--service-node-port-range=30000-50000 \
--tls-cert-file=/etc/kubernetes/ssl/server.pem \
--tls-private-key-file=/etc/kubernetes/ssl/server-key.pem \
--client-ca-file=/etc/kubernetes/ssl/ca.pem \
--service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \
--etcd-cafile=/etc/etcd/ssl/ca.pem \
--etcd-certfile=/etc/etcd/ssl/server.pem \
--etcd-keyfile=/etc/etcd/ssl/server-key.pem"
```

4. 创建apiserver启动文件

```
[root@master01 kubernetes]# more /usr/lib/systemd/system/kube-apiserver.service 
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-apiserver
ExecStart=/usr/bin/kube-apiserver $KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

5. 启动kube-apiserver

```
[root@master01 ~]# systemctl daemon-reload
[root@master01 ~]# systemctl enable kube-apiserver
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-apiserver.service to /usr/lib/systemd/system/kube-apiserver.service.
[root@master01 ~]# systemctl start kube-apiserver
[root@master01 ~]# systemctl status kube-apiserver
● kube-apiserver.service - Kubernetes API Server
   Loaded: loaded (/usr/lib/systemd/system/kube-apiserver.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2019-05-08 13:41:43 CST; 4s ago
     Docs: https://github.com/kubernetes/kubernetes
 Main PID: 45720 (kube-apiserver)
    Tasks: 14
   Memory: 44.8M
   CGroup: /system.slice/kube-apiserver.service
           └─45720 /usr/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 --bind-address=192.168...

May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.111082   45720 reflector.go:169] Listing and watching *autoscaling.HorizontalPodAutoscaler from storage/cacher....dautoscalers
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.158671   45720 compact.go:54] compactor already exists for endpoints [https://192.168.1.161:2379 https://192.16....1.163:2379]
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.159226   45720 store.go:1414] Monitoring jobs.batch count at <storage-prefix>//jobs
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.159543   45720 storage_factory.go:285] storing cronjobs.batch in batch/v1beta1, reading as batch/__internal fro...:2379"}, Key
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.161091   45720 reflector.go:169] Listing and watching *batch.Job from storage/cacher.go:/jobs
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.208372   45720 compact.go:54] compactor already exists for endpoints [https://192.168.1.161:2379 https://192.16....1.163:2379]
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.208760   45720 store.go:1414] Monitoring cronjobs.batch count at <storage-prefix>//cronjobs
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.208798   45720 master.go:415] Enabling API group "batch".
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.208867   45720 reflector.go:169] Listing and watching *batch.CronJob from storage/cacher.go:/cronjobs
May 08 13:41:47 master01 kube-apiserver[45720]: I0508 13:41:47.211855   45720 storage_factory.go:285] storing certificatesigningrequests.certificates.k8s.io in certificates.k...:2379", "htt
Hint: Some lines were ellipsized, use -l to show in full.
[root@master01 ~]# ps -ef|grep kube-apiserver 
root      45720      1 99 13:41 ?        00:00:21 /usr/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 --bind-address=192.168.1.161 --secure-port=6443 --advertise-address=192.168.1.161 --allow-privileged=true --service-cluster-ip-range=10.254.0.0/16 --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction --authorization-mode=RBAC,Node --enable-bootstrap-token-auth --token-auth-file=/etc/kubernetes/token.csv --service-node-port-range=30000-50000 --tls-cert-file=/etc/kubernetes/ssl/server.pem --tls-private-key-file=/etc/kubernetes/ssl/server-key.pem --client-ca-file=/etc/kubernetes/ssl/ca.pem --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem --etcd-cafile=/etc/etcd/ssl/ca.pem --etcd-certfile=/etc/etcd/ssl/server.pem --etcd-keyfile=/etc/etcd/ssl/server-key.pem
root      45756  33854  0 13:41 pts/1    00:00:00 grep --color=auto kube-apiserver
[root@master01 ~]# netstat -tulpn |grep kube-apiserve
tcp        0      0 192.168.1.161:6443      0.0.0.0:*               LISTEN      45720/kube-apiserve 
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      45720/kube-apiserve
```

6. 拷贝配置及启动文件至其他master上, 并且启动

```
# kube-apiserver 必须修改本地ip地址再启动
[root@master01 kubernetes]# scp -rp token.csv kube-apiserver ssl root@master02:/etc/kubernetes/
[root@master01 kubernetes]# scp -rp token.csv kube-apiserver ssl root@master03:/etc/kubernetes/

[root@master01 kubernetes]# scp -rp /usr/lib/systemd/system/kube-apiserver.service root@master03:/usr/lib/systemd/system/
[root@master01 kubernetes]# scp -rp /usr/lib/systemd/system/kube-apiserver.service root@master03:/usr/lib/systemd/system/

# master02 
[root@master02 kubernetes]# systemctl daemon-reload
[root@master02 kubernetes]# systemctl enable kube-apiserver
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-apiserver.service to /usr/lib/systemd/system/kube-apiserver.service.
[root@master02 kubernetes]# systemctl start kube-apiserver
[root@master02 kubernetes]# systemctl satus kube-apiserver
Unknown operation 'satus'.
[root@master02 kubernetes]# systemctl status kube-apiserver
● kube-apiserver.service - Kubernetes API Server
   Loaded: loaded (/usr/lib/systemd/system/kube-apiserver.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2019-05-08 13:46:44 CST; 7s ago
     Docs: https://github.com/kubernetes/kubernetes
 Main PID: 40807 (kube-apiserver)
    Tasks: 15
   Memory: 63.5M
   CGroup: /system.slice/kube-apiserver.service
           └─40807 /usr/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 --bind-address=192.168...

May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.761576   40807 storage_factory.go:285] storing controllerrevisions.apps in apps/v1, reading as apps/__internal ...163:2379"}, 
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.764015   40807 reflector.go:169] Listing and watching *apps.StatefulSet from storage/cacher.go:/statefulsets
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.809093   40807 compact.go:54] compactor already exists for endpoints [https://192.168.1.161:2379 https://192.16....1.163:2379]
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.810982   40807 store.go:1414] Monitoring controllerrevisions.apps count at <storage-prefix>//controllerrevisions
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.833179   40807 reflector.go:169] Listing and watching *apps.ControllerRevision from storage/cacher.go:/controllerrevisions
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.860614   40807 storage_factory.go:285] storing deployments.apps in apps/v1, reading as apps/__internal from sto..."}, KeyFile:
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.910576   40807 compact.go:54] compactor already exists for endpoints [https://192.168.1.161:2379 https://192.16....1.163:2379]
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.919370   40807 store.go:1414] Monitoring deployments.apps count at <storage-prefix>//deployments
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.919918   40807 reflector.go:169] Listing and watching *apps.Deployment from storage/cacher.go:/deployments
May 08 13:46:51 master02 kube-apiserver[40807]: I0508 13:46:51.921091   40807 storage_factory.go:285] storing statefulsets.apps in apps/v1, reading as apps/__internal from st...9"}, KeyFile
Hint: Some lines were ellipsized, use -l to show in full.
[root@master02 kubernetes]# ps -ef|grep kube-apiserver 
root      40807      1 99 13:46 ?        00:00:16 /usr/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 --bind-address=192.168.1.162 --secure-port=6443 --advertise-address=192.168.1.162 --allow-privileged=true --service-cluster-ip-range=10.254.0.0/16 --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction --authorization-mode=RBAC,Node --enable-bootstrap-token-auth --token-auth-file=/etc/kubernetes/token.csv --service-node-port-range=30000-50000 --tls-cert-file=/etc/kubernetes/ssl/server.pem --tls-private-key-file=/etc/kubernetes/ssl/server-key.pem --client-ca-file=/etc/kubernetes/ssl/ca.pem --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem --etcd-cafile=/etc/etcd/ssl/ca.pem --etcd-certfile=/etc/etcd/ssl/server.pem --etcd-keyfile=/etc/etcd/ssl/server-key.pem
root      40841  28766  0 13:46 pts/0    00:00:00 grep --color=auto kube-apiserver
[root@master02 kubernetes]# netstat -tulpn |grep kube-apiserve
tcp        0      0 192.168.1.162:6443      0.0.0.0:*               LISTEN      40807/kube-apiserve 
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      40807/kube-apiserve

# master03
[root@master03 ~]# systemctl daemon-reload
[root@master03 ~]# systemctl enable kube-apiserver
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-apiserver.service to /usr/lib/systemd/system/kube-apiserver.service.
[root@master03 ~]# vim /etc/kubernetes/kube-apiserver 
[root@master03 ~]# systemctl start kube-apiserver
[root@master03 ~]# systemctl status kube-apiserver
● kube-apiserver.service - Kubernetes API Server
   Loaded: loaded (/usr/lib/systemd/system/kube-apiserver.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2019-05-08 13:52:04 CST; 6s ago
     Docs: https://github.com/kubernetes/kubernetes
 Main PID: 41085 (kube-apiserver)
    Tasks: 14
   Memory: 42.8M
   CGroup: /system.slice/kube-apiserver.service
           └─41085 /usr/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 --bind-address=192.168...

May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.845049   41085 master.go:415] Enabling API group "extensions".
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.845173   41085 reflector.go:169] Listing and watching *networking.NetworkPolicy from storage/cacher.go:/networkpolicies
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.845261   41085 storage_factory.go:285] storing networkpolicies.networking.k8s.io in networking.k8s.io/v1, readi...68.1.162:237
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.912642   41085 compact.go:54] compactor already exists for endpoints [https://192.168.1.161:2379 https://192.16....1.163:2379]
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.913770   41085 store.go:1414] Monitoring networkpolicies.networking.k8s.io count at <storage-prefix>//networkpolicies
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.913808   41085 master.go:415] Enabling API group "networking.k8s.io".
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.914217   41085 reflector.go:169] Listing and watching *networking.NetworkPolicy from storage/cacher.go:/networkpolicies
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.914295   41085 storage_factory.go:285] storing poddisruptionbudgets.policy in policy/v1beta1, reading as policy...//192.168.1.
May 08 13:52:10 master03 kube-apiserver[41085]: I0508 13:52:10.996224   41085 compact.go:54] compactor already exists for endpoints [https://192.168.1.161:2379 https://192.16....1.163:2379]
May 08 13:52:11 master03 kube-apiserver[41085]: I0508 13:52:10.998244   41085 store.go:1414] Monitoring poddisruptionbudgets.policy count at <storage-prefix>//poddisruptionbudgets
May 08 13:52:11 master03 kube-apiserver[41085]: I0508 13:52:10.999020   41085 storage_factory.go:285] storing podsecuritypolicies.policy in policy/v1beta1, reading as policy/.../192.168.1.1
Hint: Some lines were ellipsized, use -l to show in full.
[root@master03 ~]# ps -ef|grep kube-apiserver 
root      41085      1 99 13:52 ?        00:00:18 /usr/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.1.161:2379,https://192.168.1.162:2379,https://192.168.1.163:2379 --bind-address=192.168.1.163 --secure-port=6443 --advertise-address=192.168.1.163 --allow-privileged=true --service-cluster-ip-range=10.254.0.0/16 --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction --authorization-mode=RBAC,Node --enable-bootstrap-token-auth --token-auth-file=/etc/kubernetes/token.csv --service-node-port-range=30000-50000 --tls-cert-file=/etc/kubernetes/ssl/server.pem --tls-private-key-file=/etc/kubernetes/ssl/server-key.pem --client-ca-file=/etc/kubernetes/ssl/ca.pem --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem --etcd-cafile=/etc/etcd/ssl/ca.pem --etcd-certfile=/etc/etcd/ssl/server.pem --etcd-keyfile=/etc/etcd/ssl/server-key.pem
root      41122  28734  0 13:52 pts/0    00:00:00 grep --color=auto kube-apiserver
[root@master03 ~]# netstat -tulpn |grep kube-apiserve
tcp        0      0 192.168.1.163:6443      0.0.0.0:*               LISTEN      41085/kube-apiserve 
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      41085/kube-apiserve
```
### 部署kube-scheduler组件

1. 创建kube-scheduler配置文件
```
[root@master01 kubernetes]# more /etc/kubernetes/kube-scheduler 
KUBE_SCHEDULER_OPTS="--logtostderr=true --v=4 --master=127.0.0.1:8080 --leader-elect"
```

2. 创建kube-scheduler启动文件
```
[root@master01 kubernetes]# more /usr/lib/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-scheduler
ExecStart=/usr/bin/kube-scheduler $KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

3. 启动服务
```
[root@master01 kubernetes]# systemctl daemon-reload
[root@master01 kubernetes]# systemctl enable kube-scheduler.service 
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-scheduler.service to /usr/lib/systemd/system/kube-scheduler.service.
[root@master01 kubernetes]# systemctl start kube-scheduler.service
[root@master01 kubernetes]# systemctl status kube-scheduler.service
● kube-scheduler.service - Kubernetes Scheduler
   Loaded: loaded (/usr/lib/systemd/system/kube-scheduler.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2019-05-08 13:56:09 CST; 4s ago
     Docs: https://github.com/kubernetes/kubernetes
 Main PID: 46894 (kube-scheduler)
    Tasks: 13
   Memory: 12.6M
   CGroup: /system.slice/kube-scheduler.service
           └─46894 /usr/bin/kube-scheduler --logtostderr=true --v=4 --master=127.0.0.1:8080 --leader-elect

May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.433278   46894 reflector.go:131] Starting reflector *v1.Node (0s) from k8s.io/client-go/informers/factory.go:132
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.433300   46894 reflector.go:169] Listing and watching *v1.Node from k8s.io/client-go/informers/factory.go:132
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.434063   46894 reflector.go:131] Starting reflector *v1.Pod (0s) from k8s.io/kubernetes/cmd/kube-scheduler/app/server.go:232
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.434084   46894 reflector.go:169] Listing and watching *v1.Pod from k8s.io/kubernetes/cmd/kube-scheduler/app/server.go:232
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.430728   46894 reflector.go:131] Starting reflector *v1.Service (0s) from k8s.io/client-go/informers/factory.go:132
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.435209   46894 reflector.go:169] Listing and watching *v1.Service from k8s.io/client-go/informers/factory.go:132
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.531262   46894 shared_informer.go:123] caches populated
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.632033   46894 shared_informer.go:123] caches populated
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.733224   46894 shared_informer.go:123] caches populated
May 08 13:56:13 master01 kube-scheduler[46894]: I0508 13:56:13.834797   46894 shared_informer.go:123] caches populated
[root@master01 kubernetes]# ps aux | grep kube-scheduler
root      46894 31.2  0.3 140056 24156 ?        Ssl  13:56   0:09 /usr/bin/kube-scheduler --logtostderr=true --v=4 --master=127.0.0.1:8080 --leader-elect
root      46945  0.0  0.0 112708   984 pts/1    S+   13:56   0:00 grep --color=auto kube-scheduler
[root@master01 kubernetes]# netstat -tnlp | grep scheduler         
[root@master01 kubernetes]# netstat -tnlp | grep schedule
tcp6       0      0 :::10251                :::*                    LISTEN      46894/kube-schedule 
tcp6       0      0 :::10259                :::*                    LISTEN      46894/kube-schedule 
```
4. 拷贝配置及启动文件至其他master上, 并且启动
```
[root@master01 kubernetes]# scp -rp kube-scheduler root@master02:/etc/kubernetes/ 
[root@master01 kubernetes]# scp -rp kube-scheduler root@master03:/etc/kubernetes/  
[root@master01 kubernetes]# scp -rp /usr/lib/systemd/system/kube-scheduler.service root@master02:/usr/lib/systemd/system/    
[root@master01 kubernetes]# scp -rp /usr/lib/systemd/system/kube-scheduler.service root@master03:/usr/lib/systemd/system/ 

# master02
[root@master02 kubernetes]# systemctl daemon-reload
[root@master02 kubernetes]# systemctl enable kube-scheduler.service 
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-scheduler.service to /usr/lib/systemd/system/kube-scheduler.service.
[root@master02 kubernetes]# systemctl start kube-scheduler.service
[root@master02 kubernetes]# systemctl status kube-scheduler.service

# master03
[root@master03 kubernetes]# systemctl daemon-reload
[root@master03 kubernetes]# systemctl enable kube-scheduler.service 
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-scheduler.service to /usr/lib/systemd/system/kube-scheduler.service.
[root@master03 kubernetes]# systemctl start kube-scheduler.service
[root@master03 kubernetes]# systemctl status kube-scheduler.service
```

### 部署kube-controller-manager组件

1. 创建kube-controller-manager配置
```
[root@master01 kubernetes]# more /etc/kubernetes/kube-controller-manager 
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=true \
--v=4 \
--master=127.0.0.1:8080 \
--leader-elect=true \
--address=127.0.0.1 \
--service-cluster-ip-range=10.254.0.0/16 \
--cluster-name=kubernetes \
--cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \
--cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
--root-ca-file=/etc/kubernetes/ssl/ca.pem \
--service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem"
```

2. 创建kube-controller-manager启动文件
```
[root@master01 kubernetes]# more /usr/lib/systemd/system/kube-controller-manager.service 
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-controller-manager
ExecStart=/usr/bin/kube-controller-manager $KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

3. 启动服务
```
[root@master01 kubernetes]# systemctl daemon-reload
[root@master01 kubernetes]# systemctl enable kube-controller-manager
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-controller-manager.service to /usr/lib/systemd/system/kube-controller-manager.service.
[root@master01 kubernetes]# systemctl start kube-controller-manager
[root@master01 kubernetes]# systemctl status kube-controller-manager
● kube-controller-manager.service - Kubernetes Controller Manager
   Loaded: loaded (/usr/lib/systemd/system/kube-controller-manager.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2019-05-08 14:03:11 CST; 3s ago
     Docs: https://github.com/kubernetes/kubernetes
 Main PID: 47513 (kube-controller)
    Tasks: 9
   Memory: 15.0M
   CGroup: /system.slice/kube-controller-manager.service
           └─47513 /usr/bin/kube-controller-manager --logtostderr=true --v=4 --master=127.0.0.1:8080 --leader-elect=true --address=127.0.0.1 --service-cluster-ip-range=10.254.0.0/16 --cl...

May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235349   47513 flags.go:33] FLAG: --tls-cipher-suites="[]"
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235373   47513 flags.go:33] FLAG: --tls-min-version=""
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235392   47513 flags.go:33] FLAG: --tls-private-key-file=""
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235411   47513 flags.go:33] FLAG: --tls-sni-cert-key="[]"
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235448   47513 flags.go:33] FLAG: --unhealthy-zone-threshold="0.55"
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235471   47513 flags.go:33] FLAG: --use-service-account-credentials="false"
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235491   47513 flags.go:33] FLAG: --v="4"
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235511   47513 flags.go:33] FLAG: --version="false"
May 08 14:03:12 master01 kube-controller-manager[47513]: I0508 14:03:12.235798   47513 flags.go:33] FLAG: --vmodule=""
May 08 14:03:14 master01 kube-controller-manager[47513]: I0508 14:03:14.541246   47513 serving.go:318] Generated self-signed cert in-memory
[root@master01 kubernetes]# ps aux | grep kube-controller-manager
root      47513 58.5  0.8 205116 66788 ?        Ssl  14:03   0:12 /usr/bin/kube-controller-manager --logtostderr=true --v=4 --master=127.0.0.1:8080 --leader-elect=true --address=127.0.0.1 --service-cluster-ip-range=10.254.0.0/16 --cluster-name=kubernetes --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem --root-ca-file=/etc/kubernetes/ssl/ca.pem --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem
root      47553  0.0  0.0 112708   984 pts/1    S+   14:03   0:00 grep --color=auto kube-controller-manager
[root@master01 kubernetes]# netstat -tnlp | grep kube-controll
tcp        0      0 127.0.0.1:10252         0.0.0.0:*               LISTEN      47513/kube-controll 
tcp6       0      0 :::10257                :::*                    LISTEN      47513/kube-controll
```

4. 拷贝配置及启动文件至其他master上, 并且启动
```
[root@master01 kubernetes]# scp -rp kube-controller-manager root@master02:/etc/kubernetes/ 
[root@master01 kubernetes]# scp -rp kube-controller-manager root@master03:/etc/kubernetes/
[root@master01 kubernetes]# scp -rp /usr/lib/systemd/system/kube-controller-manager.service root@master02:/usr/lib/systemd/system/
[root@master01 kubernetes]# scp -rp /usr/lib/systemd/system/kube-controller-manager.service root@master03:/usr/lib/systemd/system/ 

# master02
[root@master02 kubernetes]# systemctl daemon-reload
[root@master02 kubernetes]# systemctl enable kube-controller-manager
.Created symlink from /etc/systemd/system/multi-user.target.wants/kube-controller-manager.service to /usr/lib/systemd/system/kube-controller-manager.service.
[root@master02 kubernetes]# systemctl start kube-controller-manager
[root@master02 kubernetes]# systemctl status kube-controller-manager

# master03
[root@master03 ~]# systemctl daemon-reload
[root@master03 ~]# systemctl enable kube-controller-manager
Created symlink from /etc/systemd/system/multi-user.target.wants/kube-controller-manager.service to /usr/lib/systemd/system/kube-controller-manager.service.
[root@master03 ~]# systemctl start kube-controller-manager
[root@master03 ~]# systemctl status kube-controller-manager
```

## 检查集群状态

```
# master01
[root@master01 kubernetes]# kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
controller-manager   Healthy   ok                  
scheduler            Healthy   ok                  
etcd-1               Healthy   {"health":"true"}   
etcd-0               Healthy   {"health":"true"}   
etcd-2               Healthy   {"health":"true"}

# master02
[root@master02 kubernetes]# kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok                  
controller-manager   Healthy   ok                  
etcd-2               Healthy   {"health":"true"}   
etcd-1               Healthy   {"health":"true"}   
etcd-0               Healthy   {"health":"true"}

# master03
[root@master03 ~]# kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok                  
controller-manager   Healthy   ok                  
etcd-2               Healthy   {"health":"true"}   
etcd-1               Healthy   {"health":"true"}   
etcd-0               Healthy   {"health":"true"}
```

进行到这一步，master就部署完毕了，下面开始部署node组件，笔者这里也会在三台主控部署上node组件，即为主控也为node节点


