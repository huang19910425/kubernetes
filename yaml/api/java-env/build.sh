#!/bin/sh 

image_addr=harbor.kattall.com/mytest
project_name=api
url=api_v_2_1_7

deploy_dir=/root/k8s-yaml/api/dev/java/
deploy_yaml_tpl=api-deploy-tpl.yaml
deploy_yaml=api-deploy.yaml

# 打镜像, 提交镜像仓库
docker build -t $image_addr/$project_name:$url .
if [ $? -eq 0 ]; then
  docker push $image_addr/$project_name:$url
fi

# 拷贝deployment模板
cd /root/k8s-yaml/api/dev/java/ && \cp -rp $deploy_yaml_tpl $deploy_yaml

# 修改api-deploy.yaml
sed -i "s@ARGS_IMAGE@$image_addr/$project_name:$url@g" $deploy_yaml
sed -i "s@ARGS_ENV@k8s-dev@g" $deploy_yaml
sed -i "s@ARGS_URL@$url@g" $deploy_yaml

# 启动api-deploy.yaml
kubectl apply -f api-deploy.yaml
