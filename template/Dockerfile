FROM bash:latest

LABEL maintainer="sctb512@gmail.com"

ADD entrypoint.sh /entrypoint.sh
ADD file_list_path.txt /file_list_path.txt
ADD file_list_path_shuffed.txt /file_list_path_shuffed.txt

COPY REPLACE_ME REPLACE_ME

ENTRYPOINT [ "/entrypoint.sh" ]