#!/bin/bash

tmpdir=tmp
registry=docker.io/library

image_list=images.txt
target_image_list=generated_image_list.txt
target_bench_yaml=generated_bench.yaml

function large_number_small_files() {
    if [ -d ${tmpdir} ]; then
        sudo rm -rf ${tmpdir}
    fi
    mkdir ${tmpdir}
    file_number=(128 256 512 1024 2048 4096 8192 16384 32768 65536)
    file_size=(1 2 4 8 16 32 64 128)
    layer_number=(1 2 4 8 16 32 64)
    for number in ${file_number[@]}; do
        for size in ${file_size[@]}; do
            for layer in ${layer_number[@]}; do
                dir=${tmpdir}/dir_number${number}_size${size}_layer${layer}
                mkdir -p ${dir}

                kb=$((${number} * ${size}))
                kbplayer=$((${kb} / ${layer}))
                fileplayer=$((${number} / ${layer}))
                echo "number: ${number}, size: ${size}, layer: ${layer}, total ${kb}KB, per layer: ${kbplayer}KB"

                image=${registry}/nydus-small-file-test-l${layer}:n${number}-s${size}
                for i in $(cat ${image_list}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        continue
                    fi
                done

                cp template/Dockerfile ${dir}
                echo "" >${dir}/file_list_path.txt

                for l in $(seq ${layer}); do
                    layer_dir=${dir}/layer_${l}
                    mkdir -p ${layer_dir}
                    for f in $(seq ${fileplayer}); do
                        file_name=${layer_dir}/file_${f}
                        dd if=/dev/urandom of=${file_name} bs=1K count=${size} conv=notrunc >/dev/null 2>&1
                        echo "/tmp/layer_${l}/file_${f}" >>${dir}/file_list_path.txt
                    done
                    sed -i "s/^COPY REPLACE_ME.*/COPY layer_${l} \/tmp\/layer_${l}\nCOPY REPLACE_ME REPLACE_ME/g" ${dir}/Dockerfile
                done

                sed -i "/^$/d" ${dir}/file_list_path.txt
                shuf ${dir}/file_list_path.txt -o ${dir}/file_list_path_shuffed.txt

                sed -i "/^COPY REPLACE_ME.*/d" ${dir}/Dockerfile
                cp template/entrypoint.sh ${dir}

                sudo docker image load -i bash.latest
                sudo docker build -t ${image} ${dir}
                sudo docker push ${image}
                echo ${image} >>${image_list}
                rm -rf ${dir}
                sudo docker rmi -f ${image} >/dev/null 2>&1
                sudo docker system prune -a -f >/dev/null 2>&1
            done
        done
    done
}

function small_number_large_files() {
    if [ -d ${tmpdir} ]; then
        sudo rm -rf ${tmpdir}
    fi
    mkdir ${tmpdir}
    file_number=(1 2 4 8)
    file_size=(1 2 4 8)
    layer_number=(1)
    for number in ${file_number[@]}; do
        for size in ${file_size[@]}; do
            for layer in $(seq ${number}); do
                if [[ $((${number} % ${layer})) != 0 ]]; then
                    echo "skip number: ${number}, layer: ${layer}"
                    continue
                fi
                dir=${tmpdir}/dir_number${number}_size${size}_layer${layer}
                mkdir -p ${dir}

                gb=$((${number} * ${size}))
                kb=$((${number} * ${size} * ${gb} * 1024 * 1024))
                kbplayer=$((${kb} / ${layer}))
                fileplayer=$((${number} / ${layer}))
                echo "number: ${number}, size: ${size}, layer: ${layer}, total ${kb}KB, per layer: ${kbplayer}KB"

                image=${registry}/nydus-small-file-test-l${layer}:n${number}-s${size}
                for i in $(cat ${image_list}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        continue
                    fi
                done

                cp template/Dockerfile ${dir}
                echo "" >${dir}/file_list_path.txt

                for l in $(seq ${layer}); do
                    layer_dir=${dir}/layer_${l}
                    mkdir -p ${layer_dir}
                    for f in $(seq ${fileplayer}); do
                        file_name=${layer_dir}/file_${f}
                        dd if=/dev/urandom of=${file_name} bs=1G count=${size} conv=notrunc >/dev/null 2>&1
                        echo "/tmp/layer_${l}/file_${f}" >>${dir}/file_list_path.txt
                    done
                    sed -i "s/^COPY REPLACE_ME.*/COPY layer_${l} \/tmp\/layer_${l}\nCOPY REPLACE_ME REPLACE_ME/g" ${dir}/Dockerfile
                done

                sed -i "/^$/d" ${dir}/file_list_path.txt
                shuf ${dir}/file_list_path.txt -o ${dir}/file_list_path_shuffed.txt

                sed -i "/^COPY REPLACE_ME.*/d" ${dir}/Dockerfile
                cp template/entrypoint.sh ${dir}

                sudo docker image load -i bash.latest
                sudo docker build -t ${image} ${dir}
                sudo docker push ${image}
                echo ${image} >>${image_list}
                rm -rf ${dir}
                sudo docker rmi -f ${image} >/dev/null 2>&1
                sudo docker system prune -a -f >/dev/null 2>&1
            done
        done
    done
}

function large_number_random_files() {
    if [ -d ${tmpdir} ]; then
        sudo rm -rf ${tmpdir}
    fi
    mkdir ${tmpdir}
    layer_number=(1 2 4 8 16 32 64)
    for layer in ${layer_number[@]}; do
        for i in $(seq 5); do
            number=$(((RANDOM % 65536) + 100))
            for j in $(seq 5); do
                dir=${tmpdir}/dir_number${i}_size${j}_layer${layer}
                mkdir -p ${dir}

                fileplayer=$((${number} / ${layer}))
                echo "number: ${number}, layer: ${layer}, fileplayer: ${fileplayer}"

                image=${registry}/nydus-random-file-test-l${layer}:n${i}-s${j}
                for i in $(cat ${image_list}); do
                    if [[ "${i}" =~ "${image}" ]]; then
                        echo "Skip image ${image}."
                        continue
                    fi
                done

                cp template/Dockerfile ${dir}
                echo "" >${dir}/file_list_path.txt

                for l in $(seq ${layer}); do
                    layer_dir=${dir}/layer_${l}
                    mkdir -p ${layer_dir}
                    for f in $(seq ${fileplayer}); do
                        size=$(((RANDOM % 128) + 1))
                        file_name=${layer_dir}/file_${f}
                        dd if=/dev/urandom of=${file_name} bs=1K count=${size} conv=notrunc >/dev/null 2>&1
                        echo "/tmp/layer_${l}/file_${f}" >>${dir}/file_list_path.txt
                    done
                    sed -i "s/^COPY REPLACE_ME.*/COPY layer_${l} \/tmp\/layer_${l}\nCOPY REPLACE_ME REPLACE_ME/g" ${dir}/Dockerfile
                done

                sed -i "/^$/d" ${dir}/file_list_path.txt
                shuf ${dir}/file_list_path.txt -o ${dir}/file_list_path_shuffed.txt

                sed -i "/^COPY REPLACE_ME.*/d" ${dir}/Dockerfile
                cp template/entrypoint.sh ${dir}

                sudo docker image load -i bash.latest
                sudo docker build -t ${image} ${dir}
                sudo docker push ${image}
                echo ${image} >>${image_list}
                rm -rf ${dir}
                sudo docker rmi -f ${image} >/dev/null 2>&1
                sudo docker system prune -a -f >/dev/null 2>&1
            done
        done
    done
}

function generate_bench_yaml() {
    echo "" >${target_image_list}
    cp template/bench.yaml ${target_bench_yaml}
    images=($(cat ${image_list} | tr "\n" " "))
    for image in ${images[@]}; do
        repo=$(echo ${image} | awk -F\/ '{print $(NF-1)}')
        image_name=$(echo ${image} | awk -F\/ '{print $(NF)}')

        echo ${image_name} >>${target_image_list}

        name=$(echo ${image_name} | awk -F: '{print $1}')
        if [[ "${tag}" == "" ]]; then
            tag=latest
        fi
        sed -i "s/^  REPLACE_ME/- bench_args:\n    wait_line: 'Read file list done'\n  category: test\n  image: ${name}\n  repo: ${repo}\n  REPLACE_ME/g" ${target_bench_yaml}
    done
    sed -i "/REPLACE_ME/d" ${target_bench_yaml}
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
    echo -e "$0 [-t TARGET_REGISTRY] [-p TARGET_IMAGE_LIST_PATH]
[-t target registry]               \target registry for pushing image
[-p target image list path]        \tfile path that contains images list (line by line)
[-b target bench yaml path]        \tfile path for bench configuration
"
    exit -1
}

while getopts p:t:b:h OPT; do
    case $OPT in
    t)
        registry=${OPTARG}
        ;;
    p)
        target_image_list=${OPTARG}
        ;;
    b)
        target_bench_yaml=${OPTARG}
        ;;
    *)
        usage
        ;;
    esac
done
shift $((OPTIND - 1))

echo "target registry: ${registry}"
echo "target image list: ${target_image_list}"
echo "target bench yaml: ${target_bench_yaml}"

if [[ ! -f ${image_list} ]]; then
    touch ${image_list}
fi
sudo docker pull bash:latest
sudo docker image save bash:latest -o bash.latest

large_number_small_files
small_number_large_files
large_number_random_files

generate_bench_yaml
