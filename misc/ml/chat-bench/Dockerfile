FROM pytorch/pytorch:2.0.0-cuda11.7-cudnn8-devel

ADD applications/Chat /application/chat
ADD transformers /application/transformers
WORKDIR /application

RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
RUN cd /application/chat && pip install .
RUN cd /application/transformers && pip install .

ENTRYPOINT [ "/application/chat/benchmarks/benchmark_gpt_dummy.sh" ]