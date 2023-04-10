#!/bin/bash

tmpdir=tmp
accessed_list_dir=accessed_list
registry=docker.io/library

image_list=images.txt
target_image_list=generated_image_list.txt
target_bench_yaml=generated_bench.yaml
file_pattern=lbr

function large_number_small_files() {
    if [ -d ${tmpdir} ]; then
        sudo rm -rf ${tmpdir}
    fi
    mkdir ${tmpdir}
    if [ ! -d ${accessed_list_dir} ]; then
        mkdir ${accessed_list_dir}
    fi
    file_number=(128 256 512 1024 2048 4096 8192 16384)
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

                image_name=small-file-s${size}:n${number}-l${layer}
                image=${registry}/${image_name}
                for i in $(cat ${image_list}); do
                    if [[ "${i}" == "${image}" ]]; then
                        echo "Skip image ${image}."
                        continue 2
                    fi
                done
                echo "generating image ${image}..."
                image_accessed_list=${accessed_list_dir}/${image_name}

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
                cp ${image_dir}/file_list_path.txt ${image_accessed_list}
                cp ${image_dir}/file_list_path_shuffed.txt ${image_accessed_list}.shuffed

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
    if [ ! -d ${accessed_list_dir} ]; then
        mkdir ${accessed_list_dir}
    fi
    file_number=(1 2 4 8)
    file_size=(1 2 4 8)
    layer_number=(1 2)
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

                image_name=large-file-s${size}:n${number}-l${layer}
                image=${registry}/${image_name}
                for i in $(cat ${image_list}); do
                    if [[ "${i}" == "${image}" ]]; then
                        echo "Skip image ${image}."
                        continue 2
                    fi
                done
                echo "generating image ${image}..."
                image_accessed_list=${accessed_list_dir}/${image_name}

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
                cp ${image_dir}/file_list_path.txt ${image_accessed_list}
                cp ${image_dir}/file_list_path_shuffed.txt ${image_accessed_list}.shuffed

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
    if [ ! -d ${accessed_list_dir} ]; then
        mkdir ${accessed_list_dir}
    fi
    layer_number=(1 2 4 8 16 32 64)
    for layer in ${layer_number[@]}; do
        for i in $(seq 5); do
            number=$(((RANDOM % 65536) + 100))
            for j in $(seq 2); do
                dir=${tmpdir}/dir_number${i}_size${j}_layer${layer}
                mkdir -p ${dir}

                fileplayer=$((${number} / ${layer}))
                echo "number: ${number}, layer: ${layer}, fileplayer: ${fileplayer}"

                image_name=random-file-${j}:n${number}-l${layer}
                image=${registry}/${image_name}
                for i in $(cat ${image_list}); do
                    if [[ "${i}" == "${image}" ]]; then
                        echo "Skip image ${image}."
                        continue 2
                    fi
                done
                echo "generating image ${image}..."
                image_accessed_list=${accessed_list_dir}/${image_name}

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
                cp ${image_dir}/file_list_path.txt ${image_accessed_list}
                cp ${image_dir}/file_list_path_shuffed.txt ${image_accessed_list}.shuffed

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

function large_base_image_random_files() {
    if [ -d ${tmpdir} ]; then
        sudo rm -rf ${tmpdir}
    fi
    mkdir ${tmpdir}
    if [ ! -d ${accessed_list_dir} ]; then
        mkdir ${accessed_list_dir}
    fi

    file_number=(1 2 4)
    file_size=(1 2 4)
    for number in ${file_number[@]}; do
        for size in ${file_size[@]}; do
            dir=${tmpdir}/dir_number${number}_size${size}
            mkdir -p ${dir}

            mb=$((${size} * 1024))
            total_gb=$((${number} * ${size}))
            total_mb=$((${number} * ${mb}))
            echo "number: ${number}, size: ${size}, total ${total_gb}GB"

            base_image=${registry}/nydus-test-base:n${number}-s${size}
            echo "generate base images ${base_image}..."

            cp template/Dockerfile ${dir}
            echo "" >${dir}/file_list_path.txt

            base_dir=${dir}/base
            mkdir -p ${base_dir}
            for f in $(seq ${number}); do
                file_name=${base_dir}/file_${f}
                echo "dd if=/dev/urandom of=${file_name} bs=1M count=${total_mb} conv=notrunc"
                dd if=/dev/urandom of=${file_name} bs=1M count=${total_mb} conv=notrunc >/dev/null 2>&1
                echo "/tmp/base/file_${f}" >>${dir}/file_list_path.txt
            done
            sed -i "s/^COPY REPLACE_ME.*/COPY base \/tmp\/base\nCOPY REPLACE_ME REPLACE_ME/g" ${dir}/Dockerfile

            sed -i "/^$/d" ${dir}/file_list_path.txt

            sed -i "/^ADD file_list_path_shuffed.txt.*/d" ${dir}/Dockerfile
            sed -i "/^COPY REPLACE_ME.*/d" ${dir}/Dockerfile
            sed -i "/^ENTRYPOINT.*/d" ${dir}/Dockerfile
            sed -i "/^ADD entrypoint.sh.*/d" ${dir}/Dockerfile

            layer_number=(1 2 4)
            for layer in ${layer_number[@]}; do
                for i in $(seq 2); do
                    image_file_number=$(((RANDOM % 8192) + 64))

                    image_dir=${dir}/dir_base_n${number}_s${size}_upper_number${i}_size${j}_layer${layer}
                    mkdir -p ${image_dir}

                    fileplayer=$((${image_file_number} / ${layer}))
                    echo "image_file_number: ${image_file_number}, layer: ${layer}, fileplayer: ${fileplayer}"

                    image_name=base-n${number}-s${size}-f${image_file_number}-l${layer}
                    image=${registry}/${image_name}
                    for j in $(cat ${image_list}); do
                        if [[ "${i}" == "${image}" ]]; then
                            echo "Skip image ${image}."
                            continue 2
                        fi
                    done
                    echo "generating image ${image}..."
                    image_accessed_list=${accessed_list_dir}/${image_name}

                    cp template/Dockerfile ${image_dir}
                    cp ${dir}/file_list_path.txt ${image_dir}/file_list_path.txt

                    for l in $(seq ${layer}); do
                        layer_dir=${image_dir}/layer_${l}
                        mkdir -p ${layer_dir}
                        for f in $(seq ${fileplayer}); do
                            image_size=$(((RANDOM % 1024) + 1))
                            file_name=${layer_dir}/file_${f}
                            dd if=/dev/urandom of=${file_name} bs=1K count=${image_size} conv=notrunc >/dev/null 2>&1
                            echo "/tmp/layer_${l}/file_${f}" >>${image_dir}/file_list_path.txt
                        done
                        sed -i "s/^COPY REPLACE_ME.*/COPY layer_${l} \/tmp\/layer_${l}\nCOPY REPLACE_ME REPLACE_ME/g" ${image_dir}/Dockerfile
                    done

                    sed -i "/^$/d" ${image_dir}/file_list_path.txt
                    shuf ${image_dir}/file_list_path.txt -o ${image_dir}/file_list_path_shuffed.txt
                    cp ${image_dir}/file_list_path.txt ${image_accessed_list}
                    cp ${image_dir}/file_list_path_shuffed.txt ${image_accessed_list}.shuffed

                    sed -i "/^COPY REPLACE_ME.*/d" ${image_dir}/Dockerfile
                    cp template/entrypoint.sh ${image_dir}

                    sed "s|^FROM bash:latest|FROM ${base_image}|g" ${image_dir}/Dockerfile

                    sudo docker image load -i bash.latest
                    sudo docker build -t ${base_image} ${dir}

                    sudo docker build -t ${image} ${image_dir}

                    sudo docker push ${image}
                    echo ${image} >>${image_list}
                    rm -rf ${image_dir}
                    sudo docker rmi -f ${image} >/dev/null 2>&1
                    sudo docker system prune -a -f >/dev/null 2>&1

                done
            done

            rm -rf ${dir}
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
        sed -i "s/^  REPLACE_ME/- bench_args:\n    wait_line: 'Read file list done'\n    arg: seq \/file_list_path_shuffed.txt\n  category: test\n  image: ${name}\n  repo: ${repo}\n  REPLACE_ME/g" ${target_bench_yaml}
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
[-f generated file pattern]        \tfile pattern to be generated, available [
                                   \t\"ls\"\t(large number of small size files)
                                   \t\"sl\"\t(small number of large size files)
                                   \t\"lr\"\t(large number of random size files)
                                   \t\"lbr\"\t(random number of random size files with large size base image)
                                   \t\"all\"\t(all of the above) ]
"
    exit -1
}

available_operation="ls sl lr lbr all"

while getopts p:t:b:f:h OPT; do
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
    f)
        pattern=${OPTARG}
        if ! [[ "$available_pattern" =~ "$pattern" ]]; then
            echo "file pattern ${pattern} not support, use default value [${file_pattern}]"
        else
            file_pattern=${pattern}
        fi
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

if [[ ${file_pattern} == "ls" ]]; then
    large_number_small_files
fi
if [[ ${file_pattern} == "sl" ]]; then
    small_number_large_files
fi
if [[ ${file_pattern} == "lr" ]]; then
    large_number_random_files
fi
if [[ ${file_pattern} == "lbr" ]]; then
    large_base_image_random_files
fi
if [[ ${file_pattern} == "all" ]]; then
    large_number_small_files
    small_number_large_files
    large_number_random_files
    large_base_image_random_files
fi

generate_bench_yaml
