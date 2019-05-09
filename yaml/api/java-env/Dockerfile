FROM openjdk:8-jdk-alpine

MAINTAINER kattall <whatisajava@126.com>

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV TZ=Asia/Shanghai
RUN mkdir /app
WORKDIR /app

COPY run.sh /app/
ADD api.jar /app/api.jar

EXPOSE 8080
ENTRYPOINT ["sh", "/app/run.sh"]
