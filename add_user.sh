#!/bin/bash
USER=$1
PASS=$2
TAG=$3
podman exec -it crypto-scout-mq rabbitmqctl list_users
podman exec -it crypto-scout-mq rabbitmqctl add_user $USER ''$PASS''
podman exec -it crypto-scout-mq rabbitmqctl set_user_tags $USER $TAG
podman exec -it crypto-scout-mq rabbitmqctl set_permissions -p / $USER ".*" ".*" ".*"