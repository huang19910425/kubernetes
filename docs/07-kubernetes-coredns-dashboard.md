# Kubernetes系列之Coredns and Dashboard介绍篇

## 介绍

* 项目地址:https://github.com/coredns/coredns
* CoreDNS是一个Go语言实现的链式插件DNS服务端，是CNCF成员，是一个高性能、易扩展的DNS服务端。可以很方便的部署在k8s集群中，用来代替kube-dns。

## 部署coredns
```
[root@master01 coredns]# cd /root/kubernetes/yaml/coredns/
[root@master01 coredns]# kubectl apply -f coredns.yaml
serviceaccount/coredns created
clusterrole.rbac.authorization.k8s.io/system:coredns created
clusterrolebinding.rbac.authorization.k8s.io/system:coredns created
configmap/coredns created
deployment.apps/coredns created
service/kube-dns created

[root@master01 coredns]# kubectl get po -n kube-system
NAME                       READY   STATUS    RESTARTS   AGE
coredns-5d668bd598-9lfhr   1/1     Running   0          3m35s
coredns-5d668bd598-wg6rr   1/1     Running   0          3m35s

[root@master01 coredns]# kubectl logs -f coredns-5d668bd598-9lfhr -n kube-system
.:53
2019-05-08T08:00:41.392Z [INFO] CoreDNS-1.3.1
2019-05-08T08:00:41.392Z [INFO] linux/amd64, go1.11.4, 6b56a9c
CoreDNS-1.3.1
linux/amd64, go1.11.4, 6b56a9c
2019-05-08T08:00:41.392Z [INFO] plugin/reload: Running configuration MD5 = 2f886b3d3ac0d768123559b4705a7dbb
```

## 测试功能 

查看svc地址
```
[root@master01 coredns]#  kubectl get svc
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes   ClusterIP   10.254.0.1      <none>        443/TCP        141m
nginx        NodePort    10.254.247.33   <none>        80:39973/TCP   51m
[root@master01 coredns]# kubectl run -it --rm --restart=Never --image=infoblox/dnstools:latest dnstools1
If you don't see a command prompt, try pressing enter.
dnstools# ifconfig
eth0      Link encap:Ethernet  HWaddr 02:42:AC:11:1E:03  
          inet addr:172.17.30.3  Bcast:172.17.30.255  Mask:255.255.255.0
          UP BROADCAST RUNNING MULTICAST  MTU:1450  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)

lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)

dnstools# nslookup kubernetes
Server:		10.254.0.10
Address:	10.254.0.10#53

Name:	kubernetes.default.svc.cluster.local
Address: 10.254.0.1

dnstools# nslookup nginx
Server:		10.254.0.10
Address:	10.254.0.10#53

Name:	nginx.default.svc.cluster.local
Address: 10.254.247.33

dnstools# cat /etc/resolv.conf
nameserver 10.254.0.10
search default.svc.cluster.local. svc.cluster.local. cluster.local.
options ndots:5
dnstools# ping baidu.com
PING baidu.com (123.125.114.144): 56 data bytes
64 bytes from 123.125.114.144: seq=0 ttl=50 time=28.476 ms
64 bytes from 123.125.114.144: seq=1 ttl=50 time=28.867 ms
64 bytes from 123.125.114.144: seq=2 ttl=50 time=28.050 ms
^C
--- baidu.com ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 28.050/28.464/28.867 ms
dnstools# exit
pod "dnstools1" deleted
```

## 部署dashboard

> 由于国内不能下载gcr.io下的镜像，所以使用阿里云的

### 下载编排文件
```
[root@master01 ]# wget https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
```

修改其中image地址为阿里云的地址
```
spec:
containers:
- name: kubernetes-dashboard
image: registry.cn-beijing.aliyuncs.com/minminmsn/kubernetes-dashboard:v1.10.1
```

修改其中Service配置，将type: ClusterIP改成NodePort,便于通过Node端口访问
```
# ------------------- Dashboard Service ------------------- 
kind: Service
apiVersion: v1
metadata:
labels:
k8s-app: kubernetes-dashboard
name: kubernetes-dashboard
namespace: kube-system
spec:
type: NodePort
ports:
- port: 443
targetPort: 8443
selector:
k8s-app: kubernetes-dashboard
```

### 生产自定义证书

```
[root@master01 dashboard]# openssl req -nodes -newkey rsa:2048 -keyout dashboard.key -out dashboard.csr -subj "/C=/ST=/L=/O=/OU=/CN=kubernetes-dashboard"
Generating a 2048 bit RSA private key
...........+++
.....................+++
writing new private key to 'dashboard.key'
-----
No value provided for Subject Attribute C, skipped
No value provided for Subject Attribute ST, skipped
No value provided for Subject Attribute L, skipped
No value provided for Subject Attribute O, skipped
No value provided for Subject Attribute OU, skipped
[root@master01 dashboard]# openssl x509 -req -sha256 -days 365 -in dashboard.csr -signkey dashboard.key -out dashboard.crt
Signature ok
subject=/CN=kubernetes-dashboard
Getting Private key
[root@master01 dashboard]# kubectl create secret generic kubernetes-dashboard-certs --from-file=. -n kube-system
secret/kubernetes-dashboard-certs created
```

如果有购买证书的话，直接创建srcret即可
```
[root@master01 dashboard]# kubectl create secret generic kubernetes-dashboard-certs --from-file=certs -n kube-system
secret/kubernetes-dashboard-certs created
```

### 开始创建kubernetes-dashboard

```
[root@master01 dashboard]# kubectl apply -f kubernetes-dashboard.yaml 
Warning: kubectl apply should be used on resource created by either kubectl create --save-config or kubectl apply
secret/kubernetes-dashboard-certs configured
secret/kubernetes-dashboard-csrf created
serviceaccount/kubernetes-dashboard created
role.rbac.authorization.k8s.io/kubernetes-dashboard-minimal created
rolebinding.rbac.authorization.k8s.io/kubernetes-dashboard-minimal created
deployment.apps/kubernetes-dashboard created
service/kubernetes-dashboard created
```

查看服务状态
```
[root@master01 dashboard]# kubectl get pod -n kube-system -o wide
NAME                                   READY   STATUS    RESTARTS   AGE   IP            NODE            NOMINATED NODE   READINESS GATES
coredns-5d668bd598-9lfhr               1/1     Running   0          15m   172.17.30.2   192.168.1.164   <none>           <none>
coredns-5d668bd598-wg6rr               1/1     Running   0          15m   172.17.5.3    192.168.1.162   <none>           <none>
kubernetes-dashboard-cb55bd5bd-lbmth   1/1     Running   0          83s   172.17.40.2   192.168.1.165   <none>           <none>

[root@master01 dashboard]# kubectl get ep -n kube-system -o wide
NAME                      ENDPOINTS                                                 AGE
kube-controller-manager   <none>                                                    132m
kube-dns                  172.17.30.2:53,172.17.5.3:53,172.17.30.2:53 + 3 more...   16m
kube-scheduler            <none>                                                    139m
kubernetes-dashboard      172.17.40.2:8443                                          118s

[root@master01 dashboard]# kubectl get svc -n kube-system -o wide
NAME                   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                  AGE     SELECTOR
kube-dns               ClusterIP   10.254.0.10      <none>        53/UDP,53/TCP,9153/TCP   16m     k8s-app=kube-dns
kubernetes-dashboard   NodePort    10.254.254.187   <none>        443:44585/TCP            2m19s   k8s-app=kubernetes-dashboard

```

### 浏览器访问

选择token访问，token获取方法如下:
```
[root@master01 dashboard]# more dashboard-rbac.yaml 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
  namespace: kube-system
  labels: 
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin
  annotations: 
    rbac.authorization.kubernetes.io/autoupdate: "true"
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: admin
  namespace: kube-system

[root@master01 dashboard]# kubectl apply -f dashboard-rbac.yaml 
serviceaccount/admin created
clusterrolebinding.rbac.authorization.k8s.io/admin created
[root@master01 dashboard]# kubectl describe secret/$(kubectl get secret -nkube-system |grep admin|awk '{print $1}') -nkube-system
Name:         admin-token-vvppx
Namespace:    kube-system
Labels:       <none>
Annotations:  kubernetes.io/service-account.name: admin
              kubernetes.io/service-account.uid: dcf473e1-7169-11e9-9a54-000c295de02b

Type:  kubernetes.io/service-account-token

Data
====
namespace:  11 bytes
token:      eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJhZG1pbi10b2tlbi12dnBweCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJhZG1pbiIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6ImRjZjQ3M2UxLTcxNjktMTFlOS05YTU0LTAwMGMyOTVkZTAyYiIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDprdWJlLXN5c3RlbTphZG1pbiJ9.5w-S6va3EcYlhFSa8CQJt-y-TvU7yCHqDGHDpbOD-z9Oe0a3d4Ps3J0vPoxsAvIv1RYlZEY_WiIrMTLg4G5M2Mngb7bBObOXEQ1B1TGTin6ErIZxDlTJqVRuo7CyFoka-NX3kz8gvueFwdM2RnvkNC4_0ZzLRrIwNQMbgG35yNVclOn-4h2cAkfMSG9rNvV0HNex5fVWCUsN_b3_vR4Mv8oIzHF2y-k6p2tO0B4ts5-pn9MXk7CNdjSsnqtcGgIVOU1kWfzanSV7ui3E1PRVkDEvbdlu_uPBUWkXUgBJU-y_WkRLLeG6rrD3xqv7j1eFeTfUxrnngTW0I_U73iNoNQ
ca.crt:     1363 bytes
```

```
[root@master01 dashboard]# kubectl get svc -n kube-system
NAME                   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                  AGE
kube-dns               ClusterIP   10.254.0.10      <none>        53/UDP,53/TCP,9153/TCP   23m
kubernetes-dashboard   NodePort    10.254.254.187   <none>        443:44585/TCP            8m53s
```
访问任意一个节点IP端口是NodePort动态生成的, 此处为44585
出现如下页面，选择令牌，输出刚查出的token，点击登录：
![](../images/dashboard-login.png)

首页如下：
![](../images/dashboard.png)

好了，本章介绍了如何部署k8s组件coredns和dashboard，敬请期待后续分享，谢谢