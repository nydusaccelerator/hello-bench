# HelloBench

HelloBench is originally authored by @tylerharter. The original repository is not active for quite a long time. I forked the repository from commit `0fa7a8c7950615cb5aae04a85226f04f88ad3bda`.
As Python2 had reached its EOL, hello-bench adapts Python3 to attract more young python developers.

Nowadays, several container image acceleration solutions around containerd and CRI-O/podman are being introduced. This forked project is aiming at building a universal container startup benchmark tool. Acceleration images usually differs OCI images by image tags. So the improved hello-bench can receive image tags now.

## Run HelloBench

This repository just contains the benchmark harness than runs various Docker, OCI and other acceleration container images e.g. nydus and stargz.

Please ensure your `nerdctl` is beyond v0.22

Both docker and containerd can manage container images. Containerd has more a flexible mechanism - snapshots - to add plugin and manage containers images. To run benchmark for different container engines, change hello-bench argument `--engine`.

- docker for Docker
- nerdctl for Containerd

```shell
./hello.py --engine nerdctl --op run --images python:3.7
./hello.py --engine docker --op run --images python:3.7

# To run benchmark for nydus snapshotter.
./hello.py --engine nerdctl --snapshotter nydus --op run --registry=gechangwei --images python:3.7-nydus
```

## Examples

TODO
