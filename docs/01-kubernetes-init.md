# kubernetes集群搭建之系统初始化配置篇

## kubernetes的几种部署方式

### 1. minikube

Minikube是一个工具, 可以在本地快速运行一个单节点的kubernetes, 尝试kubernetes或日常开发的用户使用, 不能用于生产环境.

### 2. kubeadm

kubeadm也是一个工具, 提供kubeadm init和kubeadm join指令, 用于快速部署kubernetes集群.

### 3. 二进制包

从官方下载发行版的二进制包, 手动部署每个组件, 组成kubernetes集群.

>小结：生产环境中部署kubernetes集群, 只有kubeadm和二进制包可选, kubeadm降低部署门槛, 但屏蔽了很多细节, 遇到问题很难排查. 所有本系列使用二进制包部署kubernetes集群, 也是比较推荐大家使用这种方式, 虽然手动部署麻烦点, 但学习很多工作部署, 更有利于后期维护.

kubernetes的介绍就不过多讲了, 请移步官网。开始部署之前我们还得准备初始化工作, 这对于线上环境, 这一步必不可少的.

## 架构说明

本次系统实战环境由6台服务器组成, 为高可靠设计, etcd集群， kubernetes三主节点，保证集群的高可用性.(建议配置问4c16g) 一台镜像仓库节点(建议配合为2c4g), 一台应用节点, 最好每个节点挂个数据盘给Docker使用. 

ip地址|配置|主机名|服务
--|:--:|--:|--:
192.168.1.161|4c8g|master01|docker, flanneld, etcd, kube-apiserver, kube-scheduler, kube-Controller-manager, kubelet, kube-proxy
192.168.1.162|4c8g|master02|docker, flanneld, etcd, kube-apiserver, kube-scheduler, kube-Controller-manager, kubelet, kube-proxy
192.168.1.163|4c8g|master03|docker, flanneld, etcd, kube-apiserver, kube-scheduler, kube-Controller-manager, kubelet, kube-proxy
192.168.1.164|4c8g|node01|docker, flanneld, kubelet, kube-proxy
192.168.1.165|4c8g|node02|docker, flanneld, kubelet, kube-proxy
192.168.1.166|2c4g|harbor|docker, harbor


## 安装要求

在所有节点统一安装CentOS7.x x86 64位(推荐使用Centos 7.6), 且没有安装部署过其他软件.
所有节点均安装ssh服务, 可以root账号通过ssh方式登录.

## 版本信息

系统版本 Centos7.6
Kubernetes: v1.13
Etcd: v3.3.12
Flanneld: v0.11.0
Docker: 18.09-ce
Harbor: v1.7.0

初始化项主要有主机名修改，关闭SELinux及防火墙，limits设置，hosts配置， 服务器时区修改，主机历史命令配置

注意：需要6台都执行.

## 克隆kubernetes所需配置文件及安装包

[root@master01 ~]# git clone http://gitlab.inglemirepharms.cn/yunwei/kubernetes.git

## 主机名设置

```
192.168.1.161:
~]# hostnamectl set-hostname master01
192.168.1.162:
~]# hostnamectl set-hostname master02
192.168.1.163:
~]# hostnamectl set-hostname master03
192.168.1.164:
~]# hostnamectl set-hostname node01
192.168.1.165:
~]# hostnamectl set-hostname node02
192.168.1.166:
~]# hostnamectl set-hostname harbor
```

## 关闭SELinux及卸载防火墙

```
~]# systemctl status firewalld
~]# sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
~]# sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
~]# setenforce 0
~]# systemctl remove firewalld -y
```

## hosts设置

```
~]# more /etc/hosts
192.168.1.161 master01 
192.168.1.162 master02
192.168.1.163 master03
192.168.1.164 node01
192.168.1.165 node02
192.168.1.166 harbor harbor.kattall.com
```

## 服务器时区修改
```
~]# timedatectl set-timezone Asia/Shanghai
```

## 主机历史命令配置
```
~]# USER_IP=`who -u am i 2>/dev/null| awk '{print $NF}'|sed -e 's/[()]//g'`
~]# HISTFILESIZE=4000 
~]# HISTSIZE=4000 
~]# HISTTIMEFORMAT="%F %T ${USER_IP} `whoami` " 
~]# export HISTTIMEFORMAT
~]# source /etc/profile
```
## 做好各节点ssh互信
```
[root@master01 ~]# ssh-keygen -t rsa
[root@master01 ~]# ssh-copy-id -i root@master01
[root@master01 ~]# ssh-copy-id -i root@master02
[root@master01 ~]# ssh-copy-id -i root@master03
[root@master01 ~]# ssh-copy-id -i root@node01
[root@master01 ~]# ssh-copy-id -i root@node02
[root@master01 ~]# ssh-copy-id -i root@harbor
```

## Docker环境搭建

创建docker目录(/var/lib/docker更换为/data/app/docker)
最好可以使用单独一个磁盘作为docker目录
```
[root@master01 ~]# mkdir /data/app/docker 
[root@master01 ~]# df -h
Filesystem               Size  Used Avail Use% Mounted on
/dev/mapper/centos-root   50G  3.0G   48G   6% /
devtmpfs                 3.8G     0  3.8G   0% /dev
tmpfs                    3.9G     0  3.9G   0% /dev/shm
tmpfs                    3.9G   12M  3.8G   1% /run
tmpfs                    3.9G     0  3.9G   0% /sys/fs/cgroup
/dev/mapper/centos-home  142G   33M  142G   1% /data
/dev/sda1               1014M  146M  869M  15% /boot
tmpfs                    781M     0  781M   0% /run/user/0
[root@master01 ~]# yum install -y yum-utils device-mapper-persistent-data lvm2
[root@master01 ~]# yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

[root@master01 ~]# yum install docker-ce -y
[root@master01 ~]# systemctl start docker; systemctl enable docker

# 修改docker目录路径
[root@master01 ~]# vim /usr/lib/systemd/system/docker.service
找到 ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
改成 ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --graph /data/app/docker
[root@master01 ~]# scp /usr/lib/systemd/system/docker.service root@master02:/usr/lib/systemd/system/  
[root@master01 ~]# scp /usr/lib/systemd/system/docker.service root@master03:/usr/lib/systemd/system/   
[root@master01 ~]# scp /usr/lib/systemd/system/docker.service root@node01:/usr/lib/systemd/system/   
[root@master01 ~]# scp /usr/lib/systemd/system/docker.service root@node02:/usr/lib/systemd/system/   
[root@master01 ~]# scp /usr/lib/systemd/system/docker.service root@harbor:/usr/lib/systemd/system/
docker.service 

# 设置docker仓库地址
[root@master01 ~]# vim /etc/docker/daemon.json
{
"insecure-registries": ["harbor.kattall.com"]
}
[root@master01 ~]# scp /etc/docker/daemon.json root@master02:/etc/docker/
[root@master01 ~]# scp /etc/docker/daemon.json root@master03:/etc/docker/  
[root@master01 ~]# scp /etc/docker/daemon.json root@node01:/etc/docker/   
[root@master01 ~]# scp /etc/docker/daemon.json root@node02:/etc/docker/  
[root@master01 ~]# scp /etc/docker/daemon.json root@harbor:/etc/docker/
daemon.json 

# 重启docker
[root@master01 ~]# systemctl daemon-reload && systemctl restart docker

# 查看docker状态
[root@master01 ~]# systemctl status docker

# 查看docker目录是否切换过来, 如果原来有镜像的话，需要手动(/var/lib/docker)迁移数据.
[root@master01 ~]# ls /data/app/docker/
builder  buildkit  containers  image  network  overlay2  plugins  runtimes  swarm  tmp  trust  volumes
```

到这里, kubernetes基础环境就算搭建完成了.