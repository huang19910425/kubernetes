#!/bin/sh

kubectl delete configmap infra-wayne --namespace kube-system
kubectl create configmap infra-wayne --namespace kube-system --from-file=app.conf
