# Kubernetes系列之wayne

## 介绍

* Wayne 是一个通用的、基于 Web 的 Kubernetes 多集群管理平台。通过可视化 Kubernetes 对象模板编辑的方式，降低业务接入成本， 拥有完整的权限管理系统，适应多租户场景，是一款适合企业级集群使用的发布平台。

* Wayne已大规模服务于360搜索，承载了内部绝大部分业务，稳定管理了近千个业务，上万个容器，运行了两年多时间，经受住了生产的考验。

> 命名起源：360 搜索私有云团队多数项目命名都来源于 DC 漫画的角色，Wayne 也不例外，Wayne 是声名显赫的超级英雄蝙蝠侠 Bruce Wayne 的名字。

![](../images/wayne-dashboard.png)

## 特点

* 基于 RBAC（Role based access control）的权限管理：用户通过角色与部门和项目关联，拥有部门角色允许操作部门资源，拥有项目角色允许操作项目资源，更加适合多租户场景。
* 简化 Kubernetes 对象创建：提供基础 Kubernetes 对象配置文件添加方式，同时支持高级模式直接编辑 Json/Yaml文件创建 Kubernetes 对象。
* LDAP/OAuth 2.0/DB 多种登录模式支持：集成企业级 LDAP 登录及 DB 登录模式，同时还可以实现 OAuth2 登录。
* 支持多集群、多租户：可以同时管理多个 Kubernetes 集群，并针对性添加特定配置，更方便的多集群、多租户管理。
* 提供完整审计模块：每次操作都会有完整的审计功能，追踪用于操作历史，同时支持用户自定义 webhook。
* 提供基于 APIKey 的开放接口调用：用户可自主申请相关 APIKey 并管理自己的部门和项目，运维人员也可以申请全局 APIKey 进行特定资源的全局管理。
* 保留完整的发布历史：用户可以便捷的找到任何一次历史发布，并可轻松进行回滚，以及基于特定历史版本更新 Kubernetes 资源。
* 具备完善的资源报表：用户可以轻松获取各项目的资源使用占比和历史上线频次（天级）以及其他基础数据的报表和图表。
* 提供基于严密权限校验的 Web shell：用户可以通过 Web shell 的形式进入发布的 Pod 进行操作，自带完整的权限校验。
* 提供站内通知系统：方便管理员推送集群、业务通知和故障处理报告等。

## 架构设计

整体采用前后端分离的方案，其中前端采用 Angular 框架进行数据交互和展示，使用Ace编辑器进行 Kubernetes 资源模版编辑。后端采用 Beego 框架做数据接口处理，使用 Client-go 与 Kubernetes 进行交互，数据使用 MySQL 存储。

![](../images/wayne-app.png)


## 组件

* Web UI: 提供完整的业务开发和平台运维功能体验。
* Worker: 扩展一系列基于消息队列的功能，例如 Audit 和 Webhooks 等审计组件。

## 项目依赖

* Golang 1.9+(installation manual)
* Docker 17.05+ (installation manual)
* Bee (installation manual) (请务必使用链接版本，不要使用 beego 官方版本，存在一些定制)
* Node.js 8+ and npm 5+ (installation with nvm)
* MySQL 5.6+ (Wayne 主要数据都存在 MySQL 中)
* RabbitMQ (可选，如需扩展审计功能，例如操作审计和 Webhooks 等，则需部署)

## 部署方式(此处采用k8s的方式部署)

> yaml文件位于 kubernetes/yaml/wayne下。

wayne 依赖于 mysql 和 rabbitmq
```
[root@master01 ~]# cd kubernetes/yaml/wayne/
[root@master01 wanye]# ls
configmap.yaml  deployment.yaml  mysql.yaml  rabbitmq.yaml  service.yaml

## 以下mysql使用了pv和pvc, 如需使用请使用正确的nfs地址及路径
[root@master01 wayne]# more mysql.yaml 
apiVersion: v1
kind: PersistentVolume
metadata:
  name: wayne-mysql-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Delete
  nfs:
    server: 192.168.1.161
    path: /data/app/k8s

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wayne-mysql-pvc
  namespace: kube-system
spec:
  accessModes: 
  - ReadWriteMany
  resources:
    requests:
      storage: 100Gi

---
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: mysql-wayne
  namespace: kube-system
  labels:
    app: mysql-wayne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql-wayne
  template:
    metadata:
      labels:
        app: mysql-wayne
    spec:
      containers:
      - name: mysql
        image: 'mysql:5.7.14'
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: root
        volumeMounts:
        - name: db
          mountPath: /var/lib/mysql
        resources:
          limits:
            cpu: '1'
            memory: 2Gi
          requests:
            cpu: '1'
            memory: 2Gi
      volumes:
      - name: db
        persistentVolumeClaim:
          claimName: wayne-mysql-pvc
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: mysql-wayne
  name: mysql-wayne
  namespace: kube-system
spec:
  ports:
  - port: 3306
    protocol: TCP
    targetPort: 3306
  selector:
    app: mysql-wayne

[root@master01 wayne]# more rabbitmq.yaml 
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: rabbitmq-wayne
  namespace: kube-system
  labels:
    app: rabbitmq-wayne
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq-wayne
  template:
    metadata:
      labels:
        app: rabbitmq-wayne
    spec:
      containers:
      - name: rabbitmq
        image: 'rabbitmq:3.7.8-management'
        resources:
          limits:
            cpu: '1'
            memory: 1Gi
          requests:
            cpu: '1'
            memory: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: rabbitmq-wayne
  name: rabbitmq-wayne
  namespace: kube-system
spec:
  ports:
  - port: 5672
    protocol: TCP
    targetPort: 5672
  selector:
    app: rabbitmq-wayne

```

configmap.yaml配置
```
## 注意mysql的配置, service的名称是否是 mysql-wayne  密码是否是 root
[root@master01 wayne]# more configmap.yaml 
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: infra-wayne
  name: infra-wayne
  namespace: kube-system
data:
  app.conf: |-
    appname = wayne
    httpport = 8080
    runmode = prod
    autorender = false
    copyrequestbody = true
    EnableDocs = true
    EnableAdmin = true
    StaticDir = public:static
    # Custom config
    ShowSql = false
    ## if enable username and password login
    EnableDBLogin = true
    # token, generate jwt token
    RsaPrivateKey = "./apikey/rsa-private.pem"
    RsaPublicKey = "./apikey/rsa-public.pem"
    # token end time. second
    TokenLifeTime=86400

    # kubernetes labels config
    AppLabelKey= wayne-app
    NamespaceLabelKey = wayne-ns
    PodAnnotationControllerKindLabelKey = wayne.cloud/controller-kind

    # database configuration:
    ## mysql
    DBName = "wayne"
    DBTns = "tcp(mysql-wayne:3306)"
    DBUser = "root"
    DBPasswd = "root"
    DBLoc = "Asia%2FShanghai"
    DBConnTTL = 30

    # web shell auth
    appKey = "860af247a91a19b2368d6425797921c6"

    # Set demo namespace and group id
    DemoGroupId = "1"
    DemoNamespaceId = "1"

    # Sentry
    LogLevel = "4"
    SentryEnable = false
    SentryDSN = ""
    SentryLogLevel = "4"

    # Robin
    EnableRobin = false

    # api-keys
    EnableApiKeys = true

    # Bus
    BusEnable = true
    BusRabbitMQURL = "amqp://guest:guest@rabbitmq-wayne:5672"

    # Webhook
    EnableWebhook = true
    WebhookClientTimeout = 10
    WebhookClientWindowSize = 16
```

wayne部署
```
[root@master01 wayne]# more deployment.yaml 
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    app: infra-wayne
  name: infra-wayne
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: infra-wayne
  template:
    metadata:
      labels:
        app: infra-wayne
    spec:
      volumes:
      - name: config
        configMap:
          name: infra-wayne
      containers:
      - name: wayne
        image: '360cloud/wayne:latest'
        command:
          - /opt/wayne/backend
          - apiserver
        env:
          - name: GOPATH  # app.conf runmode = dev must set GOPATH
            value: /go
        resources:
          limits:
            cpu: '0.5'
            memory: 1Gi
          requests:
            cpu: '0.5'
            memory: 1Gi
        volumeMounts:
          - name: config
            mountPath: /opt/wayne/conf/
        readinessProbe:
          httpGet:
            path: healthz
            port: 8080
          timeoutSeconds: 1
          periodSeconds: 10
          failureThreshold: 3
        imagePullPolicy: Always
---
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: infra-wayne-woker
  namespace: kube-system
  labels:
    app: infra-wayne-woker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: infra-wayne-woker
  template:
    metadata:
      labels:
        app: infra-wayne-woker
    spec:
      volumes:
      - name: config
        configMap:
          name: infra-wayne
      containers:
      - name: wayne
        image: '360cloud/wayne:latest'
        command:
        - /opt/wayne/backend
        args:
        - worker
        - '-t'
        - AuditWorker
        - '-c'
        - '1'
        env:
        - name: GOPATH
          value: /go
        resources:
          limits:
            cpu: '0.5'
            memory: 0.5Gi
          requests:
            cpu: '0.5'
            memory: 0.5Gi
        volumeMounts:
        - name: config
          mountPath: /opt/wayne/conf/
        imagePullPolicy: Always
---
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: infra-wayne-webhook
  namespace: kube-system
  labels:
    app: infra-wayne-webhook
spec:
  replicas: 1
  selector:
    matchLabels:
      app: infra-wayne-webhook
  template:
    metadata:
      labels:
        app: infra-wayne-webhook
    spec:
      volumes:
      - name: config
        configMap:
          name: infra-wayne
      containers:
      - name: wayne
        image: '360cloud/wayne:latest'
        command:
        - /opt/wayne/backend
        args:
        - worker
        - '-t'
        - WebhookWorker
        - '-c'
        - '1'
        env:
        - value: /go
          name: GOPATH
        resources:
          limits:
            cpu: '0.5'
            memory: 0.5Gi
          requests:
            cpu: '0.5'
            memory: 0.5Gi
        volumeMounts:
        - name: config
          mountPath: /opt/wayne/conf/
        imagePullPolicy: Always
```

service.yaml
```
[root@master01 wayne]# more service.yaml 
apiVersion: v1
kind: Service
metadata:
  labels:
    app: infra-wayne
  name: infra-wayne
  namespace: kube-system
spec:
  type: NodePort
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: infra-wayne

```

启动
```
[root@master01 wayne]# ls
configmap.yaml  deployment.yaml  mysql.yaml  rabbitmq.yaml  service.yaml
[root@master01 wayne]# kubectl apply -f .

[root@master01 wayne]# kubectl get po -n kube-system
NAME                                   READY   STATUS    RESTARTS   AGE
coredns-5d668bd598-9lfhr               1/1     Running   2          23h
coredns-5d668bd598-wg6rr               1/1     Running   2          23h
infra-wayne-7ddd7f4b9c-h9ffm           1/1     Running   0          134m
infra-wayne-webhook-7f56c69675-8xzl7   1/1     Running   0          134m
infra-wayne-woker-57685f749d-bb6wk     1/1     Running   0          134m
kubernetes-dashboard-cb55bd5bd-lbmth   1/1     Running   0          23h
metrics-server-84f9775b88-zh58s        1/1     Running   0          22h
mysql-wayne-c7487479c-l9ksk            1/1     Running   0          170m
rabbitmq-wayne-79cdcbcf4-j2b8p         1/1     Running   0          3h2m

[root@master01 wayne]# kubectl get svc -n kube-system
NAME                   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                  AGE
infra-wayne            NodePort    10.254.1.212     <none>        8080:39596/TCP           134m
kube-dns               ClusterIP   10.254.0.10      <none>        53/UDP,53/TCP,9153/TCP   23h
kubernetes-dashboard   NodePort    10.254.254.187   <none>        443:44585/TCP            23h
metrics-server         ClusterIP   10.254.75.152    <none>        443/TCP                  22h
mysql-wayne            ClusterIP   10.254.5.127     <none>        3306/TCP                 170m
rabbitmq-wayne         ClusterIP   10.254.164.146   <none>        5672/TCP                 3h2m
```

通过nodeport的端口访问：

默认账号：admin    密码：admin
![](../images/wayne-login.png)

登陆后，进入后台管理，添加集群：
![](../images/wayne-add-cluster.png)

点击kubernetes-node 如下：
![](../images/wayne-cluster.png)

wayne部署完毕. 