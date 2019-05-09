#!/bin/sh

kubectl create secret tls ingle-secret --cert=inglemirepharms.cn.crt --key=inglemirepharms.cn.key
