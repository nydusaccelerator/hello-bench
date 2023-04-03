#!/bin/bash

function download_pytorch_benchmark() {
    target=$(pwd)/misc/mount/pytorch
    if [[ -d ${target} ]];then
        echo "${target} already exists"
        return
    fi
    git clone https://github.com/JunhongXu/pytorch-benchmark-volta.git $(pwd)/misc/mount/pytorch-benchmark-volta
    rm -rf $(pwd)/misc/mount/pytorch-benchmark-volta/.git
    mv $(pwd)/misc/mount/pytorch-benchmark-volta ${target}
}

function download_tf_benchmark() {
    target=$(pwd)/misc/mount/tf_cnn_benchmarks
    if [[ -d ${target} ]];then
        echo "${target} already exists"
        return
    fi
    git clone https://github.com/tensorflow/benchmarks.git $(pwd)/misc/mount/benchmarks
    mv $(pwd)/misc/mount/benchmarks/scripts/tf_cnn_benchmarks ${target}
    rm -rf $(pwd)/misc/mount/benchmarks
}

function download_model_repository() {
    target=$(pwd)/misc/mount/model_repository
    if [[ -d ${target} ]];then
        echo "${target} already exists"
        return
    fi
    mkdir -p ${target}/inception_graphdef/1
    wget -O /tmp/inception_v3_2016_08_28_frozen.pb.tar.gz \
        https://storage.googleapis.com/download.tensorflow.org/models/inception_v3_2016_08_28_frozen.pb.tar.gz
    (cd /tmp && tar xzf inception_v3_2016_08_28_frozen.pb.tar.gz)
    mv /tmp/inception_v3_2016_08_28_frozen.pb ${target}/inception_graphdef/1/model.graphdef

    mkdir -p ${target}/densenet_onnx/1
    wget -O ${target}/densenet_onnx/1/model.onnx \
        https://contentmamluswest001.blob.core.windows.net/content/14b2744cf8d6418c87ffddc3f3127242/9502630827244d60a1214f250e3bbca7/08aed7327d694b8dbaee2c97b8d0fcba/densenet121-1.2.onnx
}

download_pytorch_benchmark
download_tf_benchmark
download_model_repository