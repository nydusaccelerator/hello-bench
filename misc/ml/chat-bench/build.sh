#!/bin/bash

DIR=$(dirname "$0")

# clone ColossalAI
git clone github.com/hpcaitech/ColossalAI.git

# build chat-bench
sudo docker build -t ml_platform/chat-bench:2.0_cu117 ${DIR}