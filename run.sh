#!/bin/bash
#########################################################
# Run hello bench for OCI nydus image.  #
# Platform :All Linux Based Platform                    #
# Version  :1.0                                         #
# Date     :2022-11-09                                  #
# Author   :Bin Tang                                    #
# Contact  :tangbin.bin@bytedance.com                   #
#########################################################

#########################################################
# No need to modify
#########################################################
CURRENT_ROUND=1
RESULT_FILE=result.txt
RESULT_CSV=result.csv
NYDUSIFY_BIN=$(which nydusify)
NYDUS_IMAGE_BIN=$(which nydus-image)
BENCH_CONFIG=bench.yaml
ACCESSED_LIST_DIR=accessed_list

#########################################################
# Could alert value via arguments
#########################################################
ROUND_NUM=10
RESULT_DIR=data
SOURCE_REGISTRY=docker.io/library
TARGET_REGISTRY=""
SKIP=false
IMAGES_PATH=image_list.txt

#########################################################
# Push OCI image to TARGET_REGISTRY
# Globals:
#   TARGET_REGISTRY
# Arguments:
#   image
# Returns:
#   None
#########################################################
function push_registry() {
    image=$1
    echo "[INFO] Pushing ${image} to ${TARGET_REGISTRY}/${image}"

    sudo docker pull ${image}
    sudo docker tag ${SOURCE_REGISTRY}/${image} ${TARGET_REGISTRY}/${image}
    sudo docker push ${TARGET_REGISTRY}/${image}
    sudo docker rmi -f ${TARGET_REGISTRY}/${image}
    sudo docker rmi -f ${image}
}

#########################################################
# Convert OCI image to nydus/stargz image and push to
# TARGET_REGISTRY
# Globals:
#   TARGET_REGISTRY
# Arguments:
#   image
# Returns:
#   None
#########################################################
function convert() {
    check_binary

    image=$1

    name=$(echo ${image} | awk -F: '{print $1}')
    tag=$(echo ${image} | awk -F: '{print $2}')
    if [[ "${tag}" == "" ]];then
        tag=latest
    fi

    sudo nerdctl pull ${TARGET_REGISTRY}/${image}
    echo "[INFO] Converting ${TARGET_REGISTRY}/${image} to ${TARGET_REGISTRY}/${name}:${tag}-nydusv6 ..."
    echo "sudo $NYDUSIFY_BIN convert \
        --fs-version 6 \
        --nydus-image $NYDUS_IMAGE_BIN \
        --source ${TARGET_REGISTRY}/${image} \
        --target ${TARGET_REGISTRY}/${name}:${tag}-nydusv6"
    sudo $NYDUSIFY_BIN convert \
        --fs-version 6 \
        --nydus-image $NYDUS_IMAGE_BIN \
        --source ${TARGET_REGISTRY}/${image} \
        --target ${TARGET_REGISTRY}/${name}:${tag}-nydusv6
    
    if [[ -f ${ACCESSED_LIST_DIR}/${image} ]];then
        echo "[INFO] Converting ${TARGET_REGISTRY}/${image} to ${TARGET_REGISTRY}/${name}:${tag}-optimized-nydusv6 ..."
        echo "sudo $NYDUSIFY_BIN convert \
            --fs-version 6 \
            --nydus-image $NYDUS_IMAGE_BIN \
            --source ${TARGET_REGISTRY}/${image} \
            --target ${TARGET_REGISTRY}/${name}:${tag}-optimized-nydusv6 \
            --prefetch-patterns < ${ACCESSED_LIST_DIR}/${image}.shuffed"
        sudo $NYDUSIFY_BIN convert \
            --fs-version 6 \
            --nydus-image $NYDUS_IMAGE_BIN \
            --source ${TARGET_REGISTRY}/${image} \
            --target ${TARGET_REGISTRY}/${name}:${tag}-optimized-nydusv6 \
            --prefetch-patterns < ${ACCESSED_LIST_DIR}/${image}.shuffed
    fi
}

#########################################################
# Stop all running containers
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#########################################################
function stop_all_containers {
    containers=$(sudo nerdctl ps -q | tr '\n' ' ')
    if [[ ${containers} == "" ]]; then
        return 0
    else
        echo "Killing containers ${containers}"
        for C in ${containers}; do
            sudo nerdctl kill "${C}" >/dev/null 2>&1
            sudo nerdctl stop "${C}" >/dev/null 2>&1
            sudo nerdctl rm -f "${C}" >/dev/null 2>&1
        done
        sudo nerdctl ps -a
        sudo nerdctl images
        return 1
    fi
}

#########################################################
# Run hello bench for OCI image, nydus image
# Globals:
#   TARGET_REGISTRY
# Arguments:
#   image
# Returns:
#   None
#########################################################
function run() {
    image=$1

    name=$(echo ${image} | awk -F: '{print $1}')
    tag=$(echo ${image} | awk -F: '{print $2}')
    if [[ "${tag}" == "" ]];then
        tag=latest
    fi

    stop_all_containers
    sudo nerdctl ps -a | awk 'NR>1 {print $1}' | xargs sudo nerdctl rm >/dev/null 2>&1
    sudo nerdctl container prune -f >/dev/null 2>&1
    sudo nerdctl image prune --all -f >/dev/null 2>&1
    sudo nerdctl system prune --volumes --all -f >/dev/null 2>&1
    sudo ctr leases ls | awk 'NR>1 {print $1}' | xargs sudo ctr leases rm --sync >/dev/null 2>&1
    sudo ctr images ls | awk 'NR>1 {print $1}' | xargs sudo ctr images rm --sync >/dev/null 2>&1
    sudo ctr content prune references >/dev/null 2>&1
    sleep 1

    echo "[INFO] Run hello bench in ${image} ..."
    sudo nerdctl --snapshotter overlayfs rmi -f ${TARGET_REGISTRY}/${image} >/dev/null 2>&1
    result=$(sudo ./hello.py --bench-config=${BENCH_CONFIG} --engine nerdctl --snapshotter overlayfs --op run \
        --registry=${TARGET_REGISTRY} \
        --images ${image} |
        grep "repo" | grep "bench" | grep "timestamp")
    echo ${result}
    echo ${result} >>${RESULT_DIR}/${RESULT_FILE}.${CURRENT_ROUND}
    echo "[INFO] Remove image ${TARGET_REGISTRY}/${image} ..."
    sudo nerdctl --snapshotter overlayfs rmi -f ${TARGET_REGISTRY}/${image} >/dev/null 2>&1
}

function run_nydus() {
    image=$1

    name=$(echo ${image} | awk -F: '{print $1}')
    tag=$(echo ${image} | awk -F: '{print $2}')
    if [[ "${tag}" == "" ]];then
        tag=latest
    fi

    stop_all_containers
    sudo nerdctl ps -a | awk 'NR>1 {print $1}' | xargs sudo nerdctl rm >/dev/null 2>&1
    sudo nerdctl container prune -f >/dev/null 2>&1
    sudo nerdctl image prune --all -f >/dev/null 2>&1
    sudo nerdctl system prune --volumes --all -f >/dev/null 2>&1
    sudo ctr leases ls | awk 'NR>1 {print $1}' | xargs sudo ctr leases rm --sync >/dev/null 2>&1
    sudo ctr images ls | awk 'NR>1 {print $1}' | xargs sudo ctr images rm --sync >/dev/null 2>&1
    sudo ctr content prune references >/dev/null 2>&1
    sleep 1
    sudo lsof -nP +L1 | grep containerd | grep "(deleted)" | awk '{print $2}' | xargs sudo kill
    sleep 1
    sudo rm -rf /var/lib/containerd/nydus/cache

    echo "[INFO] Run hello bench in ${name}:${tag}-nydusv6 ..."
    sudo nerdctl --snapshotter nydus rmi -f ${TARGET_REGISTRY}/${name}:${tag}-nydusv6 >/dev/null 2>&1
    result=$(sudo ./hello.py --bench-config=${BENCH_CONFIG} --engine nerdctl --snapshotter nydus --op run \
        --registry=${TARGET_REGISTRY} \
        --images ${name}:${tag}-nydusv6 |
        grep "repo" | grep "bench" | grep "timestamp")
    echo ${result}
    echo ${result} >>${RESULT_DIR}/${RESULT_FILE}.nydus.${CURRENT_ROUND}
    echo "[INFO] Remove image ${TARGET_REGISTRY}/${name}:${tag}-nydusv6 ..."
    sudo nerdctl --snapshotter nydus rmi -f ${TARGET_REGISTRY}/${name}:${tag}-nydusv6 >/dev/null 2>&1
}

function run_optimized_nydus() {
    image=$1

    name=$(echo ${image} | awk -F: '{print $1}')
    tag=$(echo ${image} | awk -F: '{print $2}')
    if [[ "${tag}" == "" ]];then
        tag=latest
    fi

    stop_all_containers
    sudo nerdctl ps -a | awk 'NR>1 {print $1}' | xargs sudo nerdctl rm >/dev/null 2>&1
    sudo nerdctl container prune -f >/dev/null 2>&1
    sudo nerdctl image prune --all -f >/dev/null 2>&1
    sudo nerdctl system prune --volumes --all -f >/dev/null 2>&1
    sudo ctr leases ls | awk 'NR>1 {print $1}' | xargs sudo ctr leases rm --sync >/dev/null 2>&1
    sudo ctr images ls | awk 'NR>1 {print $1}' | xargs sudo ctr images rm --sync >/dev/null 2>&1
    sudo ctr content prune references >/dev/null 2>&1
    sleep 1
    sudo lsof -nP +L1 | grep containerd | grep "(deleted)" | awk '{print $2}' | xargs sudo kill
    sleep 1
    sudo rm -rf /var/lib/containerd/nydus/cache

    echo "[INFO] Run hello bench in ${name}:${tag}-optimized-nydusv6 ..."
    sudo nerdctl --snapshotter nydus rmi -f ${TARGET_REGISTRY}/${name}:${tag}-optimized-nydusv6 >/dev/null 2>&1
    result=$(sudo ./hello.py --bench-config=${BENCH_CONFIG} --engine nerdctl --snapshotter nydus --op run \
        --registry=${TARGET_REGISTRY} \
        --images ${name}:${tag}-optimized-nydusv6 |
        grep "repo" | grep "bench" | grep "timestamp")
    echo ${result}
    echo ${result} >>${RESULT_DIR}/${RESULT_FILE}.optimized.nydus.${CURRENT_ROUND}
    echo "[INFO] Remove image ${TARGET_REGISTRY}/${name}:${tag}-optimized-nydusv6 ..."
    sudo nerdctl --snapshotter nydus rmi -f ${TARGET_REGISTRY}/${name}:${tag}-optimized-nydusv6 >/dev/null 2>&1
}

#########################################################
# Handle data in $RESULT_DIR to csv and png
# Globals:
#   RESULT_DIR
# Arguments:
#   None
# Returns:
#   None
#########################################################
function handle_data() {
    python3_path=$(which python3)
    if [ "$(which python3)" == "" ]; then
        echo "[ERROR] Can not found python3"
        exit
    fi
    if [ ! -d ${RESULT_DIR} ]; then
        echo "[ERROR] Directory ${RESULT_DIR} not exist"
        exit
    fi
    ${python3_path} draw.py -d ${RESULT_DIR} -r result
}

#########################################################
# Check required options for this script
# Globals:
#   TARGET_REGISTRY
#   SOURCE_REGISTRY
# Arguments:
#   None
# Returns:
#   None
#########################################################
function check_opts() {
    if [ "${TARGET_REGISTRY}" == "" ]; then
        echo "[ERROR] TARGET_REGISTRY is null"
        exit
    fi
    if [ "${SOURCE_REGISTRY}" == "" ]; then
        echo "[ERROR] SOURCE_REGISTRY is null"
        exit
    fi
}

#########################################################
# Check required binary for this script
# Globals:
#   NYDUSIFY_BIN
#   NYDUS_IMAGE_BIN
# Arguments:
#   None
# Returns:
#   None
#########################################################
function check_binary() {
    if [ "${NYDUSIFY_BIN}" == "" ]; then
        echo "[ERROR] nydusify is not found in \$PATH"
        exit
    fi
    if [ "${NYDUS_IMAGE_BIN}" == "" ]; then
        echo "[ERROR] nydus-image is not found in \$PATH"
        exit
    fi
}

#########################################################
# Usage information
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#########################################################
function usage() {
    echo "Usage:"
    echo -e "run.sh -o OPERATION -s SOURCE_REGISTRY -t TARGET_REGISTRY [other options]
[-o operation]          \tavailable options are [ push convert run all draw ]
[-c config]             \tbench config file (only available for \"run\" operation)
[-i images]             \timages list
[-p images path]        \tfile path that contains images list (line by line)
[-s source registry]    \tsource registry for pulling image
[-t target registry]    \target registry for pushing image
[-r round number]       \tnumber of round to run hellobench
[-d result directory]   \tdirectory to store raw result data
[-k skip finished test] \tskip images that already finisned (in \$RESULT_DIR/\$RESULT_FILE)"
    exit -1
}

function getopts_extra() {
    declare i=1
    while [[ ${OPTIND} -le $# && ${!OPTIND:0:1} != '-' ]]; do
        OPTARG[i]=${!OPTIND}
        let i++ OPTIND++
    done
}

available_operation="push convert run all draw"

if [ $# -eq 0 ]; then
    usage
fi

while getopts o:c:i:p:s:t:r:d:k:h OPT; do
    case $OPT in
    o)
        operation=${OPTARG}
        if ! [[ "$available_operation" =~ "$operation" ]]; then
            echo "operation ${operation} not support now"
            exit
        fi

        ;;
    c)
        BENCH_CONFIG=${OPTARG}
        ;;
    i)
        getopts_extra "$@"
        images=("${OPTARG[@]}")
        ;;
    p)
        IMAGES_PATH=${OPTARG}
        ;;
    s)
        SOURCE_REGISTRY=${OPTARG}
        ;;
    t)
        TARGET_REGISTRY=${OPTARG}
        ;;
    r)
        ROUND_NUM=${OPTARG}
        ;;
    d)
        RESULT_DIR=${OPTARG}
        ;;
    k)
        SKIP=true
        ;;
    *)
        usage
        ;;
    esac
done
shift $((OPTIND - 1))

if [ ${#images[@]} -gt 0 ]; then
    IMAGES=()
    for image in "${images[@]}"; do
        IMAGES+=($image)
    done
else
    IMAGES=($(cat ${IMAGES_PATH} | tr "\n" " "))
fi

images_length=${#IMAGES[@]}
echo "images:"
for IMAGE in "${IMAGES[@]}"; do
    echo "- ${IMAGE}"
done

if [ ${images_length} -eq 0 ] && [ "$IMAGES_PATH" == "" ]; then
    echo "both images list and file path are null"
    exit
fi

case $operation in
push)
    check_opts
    for image in "${IMAGES[@]}"; do
        push_registry ${image}
    done
    ;;
convert)
    check_opts
    for image in "${IMAGES[@]}"; do
        convert ${image}
    done
    ;;
run)
    check_opts
    if [ ! "${SKIP}" == "true" ]; then
        if [ -d ${RESULT_DIR} ]; then
            rm -rf ${RESULT_DIR}
        fi
        mkdir ${RESULT_DIR}
    fi
    for i in $(seq 1 ${ROUND_NUM}); do
        CURRENT_ROUND=${i}
        if [ ! "${SKIP}" == "true" ]; then
            echo "" >${RESULT_DIR}/${RESULT_FILE}.${CURRENT_ROUND}
            echo "" >${RESULT_DIR}/${RESULT_FILE}.nydus.${CURRENT_ROUND}
            echo "" >${RESULT_DIR}/${RESULT_FILE}.optimized.nydus.${CURRENT_ROUND}
        fi

        for image in "${IMAGES[@]}"; do
            if [ "${SKIP}" == "true" ]; then
                skip=false
                for i in $(cat ${RESULT_DIR}/${RESULT_FILE}.${CURRENT_ROUND}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        skip=true
                        break
                    fi
                done
                if [ "${skip}" == "true" ]; then
                    continue
                fi
            fi
            run ${image}
        done
        for image in "${IMAGES[@]}"; do
            if [ "${SKIP}" == "true" ]; then
                skip=false
                for i in $(cat ${RESULT_DIR}/${RESULT_FILE}.nydus.${CURRENT_ROUND}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        skip=true
                        break
                    fi
                done
                if [ "${skip}" == "true" ]; then
                    continue
                fi
            fi
            run_nydus ${image}
        done
        for image in "${IMAGES[@]}"; do
            if [ "${SKIP}" == "true" ]; then
                skip=false
                for i in $(cat ${RESULT_DIR}/${RESULT_FILE}.optimized.nydus.${CURRENT_ROUND}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        skip=true
                        break
                    fi
                done
                if [ "${skip}" == "true" ]; then
                    continue
                fi
            fi
            run_optimized_nydus ${image}
        done
    done
    ;;
all)
    check_opts
    if [ ! "${SKIP}" == "true" ]; then
        if [ -d ${RESULT_DIR} ]; then
            rm -rf ${RESULT_DIR}
        fi
        mkdir ${RESULT_DIR}
    fi
    for i in $(seq 1 ${ROUND_NUM}); do
        CURRENT_ROUND=${i}
        if [ ! "${SKIP}" == "true" ]; then
            echo "" >${RESULT_DIR}/${RESULT_FILE}.${CURRENT_ROUND}
        fi

        for image in "${IMAGES[@]}"; do
            if [ "${SKIP}" == "true" ]; then
                skip=false
                for i in $(cat ${RESULT_DIR}/${RESULT_FILE}.${CURRENT_ROUND}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        skip=true
                        break
                    fi
                done
                if [ "${skip}" == "true" ]; then
                    continue
                fi
            fi
            if [ ${CURRENT_ROUND} -eq 1 ]; then
                push_registry ${image}
                convert ${image}
            fi
            run ${image}
        done
    done

    handle_data
    ;;
draw)
    handle_data
    ;;
*)
    echo "get invalid operation: ${operation}"
    usage
    exit
    ;;
esac
