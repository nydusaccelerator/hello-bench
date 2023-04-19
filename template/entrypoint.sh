#!/usr/bin/env bash

default_type=seq
default_file_list_path=/file_list_path.txt
if [[ $# -eq 0 ]]; then
    type=${default_type}
    path=${default_file_list_path}
else
    if [[ $# -eq 2 ]]; then
        if [[ $1 != seq && $1 != rand ]]; then
            echo "unsupported type: $1, available type: seq rand"
            exit 1
        fi
        type=$1
        path=$2
    else
        echo "Usage: $0 READ_TYPE(seq rand) FILE_LIST_PATH"
        exit 1
    fi
fi

echo "read type: $type"
echo "file list path: $path"

if [[ $type == seq ]]; then
    files=($(cat ${path} | tr "\n" " "))
    files_number=${#files[@]}
    echo "read file number: $files_number"

    for file in "${files[@]}"; do
        file_size=$(stat -c%s "${file}")
        echo "file: ${file} size: ${file_size}"
        cat ${file} >/dev/null
    done
elif [[ $type == rand ]]; then
    rand_path=${path}.rand
    shuf ${path} -o ${path}.rand

    files=($(cat ${rand_path} | tr "\n" " "))
    files_number=${#files[@]}
    echo "read file number: $files_number"

    for file in "${files[@]}"; do
        file_size=$(stat -c%s "${file}")
        echo "file: ${file} size: ${file_size}"
        cat ${file} >/dev/null
    done
fi

echo "Read file list done."
