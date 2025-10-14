#!/bin/bash

# Create network
podman network create crypto-scout-bridge
podman network inspect crypto-scout-bridge