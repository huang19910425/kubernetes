#!/bin/bash
java -jar -Djava.security.egd=file:/dev/./urandom $JAVA_OPTS /app/api.jar
