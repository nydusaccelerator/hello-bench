#!/usr/bin/env python3

# The MIT License (MIT)
#
# Copyright (c) 2015 Tintri
# Copyright (c) 2022 Changwei Ge
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import logging
import os, sys, subprocess, random, urllib.request, time, json, tempfile, shutil, copy
import posixpath
import string
from argparse import ArgumentParser
from datetime import datetime
from contextlib import contextmanager
import yaml

TMP_DIR = tempfile.mkdtemp()


def exit(status):
    # cleanup
    shutil.rmtree(TMP_DIR)
    sys.exit(status)


def tmp_dir():
    tmp_dir.nxt += 1
    return os.path.join(TMP_DIR, str(tmp_dir.nxt))


tmp_dir.nxt = 0


def logging_setup(logging_stream=sys.stderr):
    """Inspired from Kadalu project"""
    root = logging.getLogger()

    if root.hasHandlers():
        return

    verbose = True

    # Errors should also be printed to screen.
    handler = logging.StreamHandler(logging_stream)

    if verbose:
        root.setLevel(logging.DEBUG)
        handler.setLevel(logging.DEBUG)
    else:
        root.setLevel(logging.INFO)
        handler.setLevel(logging.INFO)

    formatter = logging.Formatter(
        "[%(asctime)s] %(levelname)s "
        "[%(module)s - %(lineno)s:%(funcName)s] "
        "- %(message)s"
    )
    handler.setFormatter(formatter)
    root.addHandler(handler)


logging_setup()


def random_chars():
    return "".join(random.choice(string.ascii_lowercase) for i in range(10))


def run(cmd, wait: bool = True, verbose=True, **kwargs):

    shell = kwargs.pop("shell", False)
    if shell:
        cmd = " ".join(cmd)

    if verbose:
        logging.info(cmd)
    else:
        logging.debug(cmd)

    popen_obj = subprocess.Popen(cmd, shell=shell, **kwargs)
    if wait:
        popen_obj.wait()
    return popen_obj.returncode, popen_obj


def tmp_copy(src):
    dst = tmp_dir()
    shutil.copytree(src, dst)
    return dst


def get_current_time():
    return datetime.now()


def delta_time(t_end, t_start):
    delta = t_end - t_start
    return delta.total_seconds(), delta.microseconds


@contextmanager
def timer(cmd):
    start = get_current_time()
    try:
        rc = os.system(cmd)
        assert rc == 0
        end = get_current_time()
        sec, usec = delta_time(end, start)
        yield sec + usec / 1e6
        logging.info("%s, Takes time %u.%u seconds", cmd, sec, usec)
    finally:
        pass


class RunArgs:
    def __init__(
        self, env={}, arg="", stdin="", stdin_sh="sh", waitline="", mount=[], waitURL="", runtime="", shmSize="", workDir=""
    ):
        self.env = env
        self.arg = arg
        self.stdin = stdin
        self.stdin_sh = stdin_sh
        self.waitline = waitline
        self.mount = mount
        self.waitURL = waitURL
        self.runtime = runtime
        self.shmSize = shmSize
        self.workDir = workDir


class Docker:
    def __init__(self, bin="docker"):
        self.bin = bin

    def set_image(self, ref):
        self.image_ref = ref
        return self

    def set_snapshotter(self, sn="overlayfs"):
        self.snapshotter = sn
        return self

    def run(
        self,
        network="none",
        name=None,
        background=False,
        enable_stdin=False,
        envs=[],
        run_cmd_args=None,
        volumes=[],
        stdin=None,
        stdout=None,
    ):
        cmd = [self.bin, "--snapshotter", self.snapshotter, "run"]
        cmd.append(f"--net={network}")

        if enable_stdin:
            cmd.append("-i")

        cmd.append("--rm")

        if name is not None:
            cmd.append(f"--name={name}")

        for (s, d) in volumes:
            cmd.extend(["-v", f"{s}:{d}"])

        for (k, v) in envs:
            cmd.extend(["-e", f"{k}={v}"])

        cmd.append(self.image_ref)

        if run_cmd_args is not None:
            cmd.append(run_cmd_args)

        _, p = run(
            cmd,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=sys.stdout if stdout is None else stdout,
            stderr=sys.stderr if stdout is None else stdout,
            wait=False,
        )

        if stdin is not None:
            out = p.communicate(input=stdin)

        if not background:
            p.wait()
            assert p.returncode == 0
        else:
            return p

    def kill(self, name):
        cmd = [self.bin, "kill", name]
        _, p = run(
            cmd,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=sys.stdout,
            stderr=sys.stderr,
            wait=True,
        )


class Bench:
    def __init__(self, name, category="other"):
        self.name = name
        self.repo = name  # TODO: maybe we'll eventually have multiple benches per repo
        self.category = category

    def __str__(self):
        return json.dumps(self.__dict__)

    def set_tag(self, tag):
        self.name = f"{self.name}:{tag}"


class BenchRunner:
    def __init__(
        self,
        docker="docker",
        registry="localhost:5000",
        registry2="localhost:5000",
        snapshotter="overlayfs",
        cleanup=True,
        insecure_registry=False,
        bench_config="bench.yaml",
    ):
        self.registry = registry
        if self.registry != "":
            self.registry += "/"
        self.registry2 = registry2
        if self.registry2 != "":
            self.registry2 += "/"

        self.snapshotter = snapshotter
        self.insecure_registry = insecure_registry

        self.docker = Docker(bin=docker)
        if "nerdctl" == docker:
            self.docker.set_snapshotter(snapshotter)
        self.cleanup = cleanup
        self.bench_config = bench_config

    def load_bench_config(self):
        bench_config = self.bench_config
        print(f"Loading bench configuration from {bench_config}...")
        with open(bench_config, "r") as stream:
            data = yaml.safe_load(stream)

        echo_hello_runner = set()
        echo_hello = dict()
        if "ECHO_HELLO" in data:
            for line in data["ECHO_HELLO"]:
                name = line["image"]
                echo_hello_runner.add(name)
                echo_hello[name] = Bench(name, line["category"])

        cmd_arg_wait_runner = dict()
        cmd_arg_wait = dict()
        if "CMD_ARG_WAIT" in data:
            for line in data["CMD_ARG_WAIT"]:
                name = line["image"]
                args = line["bench_args"]
                print(f"CMD_ARG_WAIT image: {name}, args: {args}")
                cmd_arg_wait_runner[name] = RunArgs(
                    env=dict([(item["key"], item["value"]) for item in args["envs"]]) if "envs" in args else {},
                    waitline=args["wait_line"] if "wait_line" in args else "",
                    mount=[(m["host_path"], m["container_path"]) for m in args["mount"]]
                    if "mount" in args
                    else [],
                    arg=args["arg"] if "arg" in args else "",
                    stdin=args["stdin"] if "stdin" in args else "",
                    stdin_sh=args["stdin_sh"] if "stdin_sh" in args else "",
                    runtime=args["runtime"] if "runtime" in args else "",
                    shmSize=args["shm_size"] if "shm_size" in args else "",
                    workDir=args["work_dir"] if "work_dir" in args else "",
                )
                cmd_arg_wait[name] = Bench(name, line["category"])

        cmd_stdin_runner = dict()
        cmd_stdin = dict()
        if "CMD_STDIN" in data:
            for line in data["CMD_STDIN"]:
                name = line["image"]
                args = line["bench_args"]
                print(f"CMD_STDIN image: {name}, args: {args}")
                cmd_stdin_runner[name] = RunArgs(
                    env=dict([(item["key"], item["value"]) for item in args["envs"]]) if "envs" in args else {},
                    mount=[(m["host_path"], m["container_path"]) for m in args["mount"]]
                    if "mount" in args
                    else [],
                    arg=args["arg"] if "arg" in args else "",
                    stdin=args["stdin"] if "stdin" in args else "",
                    stdin_sh=args["stdin_sh"] if "stdin_sh" in args else "",
                    runtime=args["runtime"] if "runtime" in args else "",
                    shmSize=args["shm_size"] if "shm_size" in args else "",
                    workDir=args["work_dir"] if "work_dir" in args else "",
                )
                cmd_stdin[name] = Bench(name, line["category"])

        cmd_arg_runner = dict()
        cmd_arg = dict()
        if "CMD_ARG" in data:
            for line in data["CMD_ARG"]:
                name = line["image"]
                args = line["bench_args"]
                print(f"CMD_ARG image: {name}, args: {args}")
                cmd_arg_runner[name] = RunArgs(
                    env=dict([(item["key"], item["value"]) for item in args["envs"]]) if "envs" in args else {},
                    mount=[(m["host_path"], m["container_path"]) for m in args["mount"]]
                    if "mount" in args
                    else [],
                    arg=args["arg"] if "arg" in args else "",
                    stdin=args["stdin"] if "stdin" in args else "",
                    stdin_sh=args["stdin_sh"] if "stdin_sh" in args else "",
                    runtime=args["runtime"] if "runtime" in args else "",
                    shmSize=args["shm_size"] if "shm_size" in args else "",
                    workDir=args["work_dir"] if "work_dir" in args else "",
                )
                cmd_arg[name] = Bench(name, line["category"])

        cmd_url_wait_runner = dict()
        cmd_url_wait = dict()
        if "CMD_URL_WAIT" in data:
            for line in data["CMD_URL_WAIT"]:
                name = line["image"]
                args = line["bench_args"]
                print(f"CMD_URL_WAIT image: {name}, args: {args}")
                cmd_url_wait_runner[name] = RunArgs(
                    env=dict([(item["key"], item["value"]) for item in args["envs"]]) if "envs" in args else {},
                    waitURL=args["wait_url"] if "wait_url" in args else "",
                    mount=[(m["host_path"], m["container_path"]) for m in args["mount"]]
                    if "mount" in args
                    else [],
                    arg=args["arg"] if "arg" in args else "",
                    stdin=args["stdin"] if "stdin" in args else "",
                    stdin_sh=args["stdin_sh"] if "stdin_sh" in args else "",
                    runtime=args["runtime"] if "runtime" in args else "",
                    shmSize=args["shm_size"] if "shm_size" in args else "",
                    workDir=args["work_dir"] if "work_dir" in args else "",
                )
                cmd_url_wait[name] = Bench(name, line["category"])

        all = {**echo_hello, **cmd_arg_wait, **cmd_stdin, **cmd_arg, **cmd_url_wait}
        print([name for name in all.keys()])

        self.ECHO_HELLO = echo_hello_runner
        self.CMD_ARG_WAIT = cmd_arg_wait_runner
        self.CMD_STDIN = cmd_stdin_runner
        self.CMD_ARG = cmd_arg_runner
        self.CMD_URL_WAIT = cmd_url_wait_runner

        self.ALL = all

    def image_ref(self, repo):
        return posixpath.join(self.registry, repo)

    def run_echo_hello(self, repo: str):
        image_ref = self.image_ref(repo)
        container_name = repo.replace(":", "-") + random_chars()

        pull_cmd = self.pull_cmd(image_ref)
        print(pull_cmd)

        print("Pulling image %s ..." % image_ref)
        with timer(pull_cmd) as t:
            pull_elapsed = t

        create_cmd = self.create_echo_hello_cmd(image_ref, container_name)
        print(create_cmd)

        print("Creating container for image %s ..." % image_ref)
        with timer(create_cmd) as t:
            create_elapsed = t

        run_cmd = self.task_start_cmd(container_name, iteration=False)
        print(run_cmd)

        print("Running container %s ..." % container_name)
        with timer(run_cmd) as t:
            run_elapsed = t
        if self.cleanup:
            self.clean_up(image_ref, container_name)

        return pull_elapsed, create_elapsed, run_elapsed

    def run_cmd_arg(self, repo, runargs):
        image_ref = self.image_ref(repo)
        container_name = repo.replace(":", "-") + random_chars()

        pull_cmd = self.pull_cmd(image_ref)
        print(pull_cmd)

        print("Pulling image %s ..." % image_ref)
        with timer(pull_cmd) as t:
            pull_elapsed = t

        create_cmd = self.create_cmd_arg_cmd(image_ref, container_name, runargs)
        print(create_cmd)

        print("Creating container for image %s ..." % image_ref)
        with timer(create_cmd) as t:
            create_elapsed = t

        run_cmd = self.task_start_cmd(container_name, iteration=False)
        print(run_cmd)

        with timer(run_cmd) as t:
            run_elapsed = t

        if self.cleanup:
            self.clean_up(image_ref, container_name)

        return pull_elapsed, create_elapsed, run_elapsed

    def run_cmd_arg_wait(self, repo, runargs):
        image_ref = self.image_ref(repo)
        container_name = repo.replace(":", "-") + random_chars()

        pull_cmd = self.pull_cmd(image_ref)
        print(pull_cmd)

        print("Pulling image %s ..." % image_ref)
        with timer(pull_cmd) as t:
            pull_elapsed = t

        create_cmd = self.create_cmd_arg_wait_cmd(image_ref, container_name, runargs)
        print(create_cmd)

        print("Creating container for image %s ..." % image_ref)
        with timer(create_cmd) as t:
            create_elapsed = t

        run_cmd = self.task_start_cmd(container_name, iteration=True)
        print(run_cmd)

        r, w = os.pipe()
        reader = os.fdopen(r)
        writer = os.fdopen(w)

        print("Running container %s ..." % container_name)
        start_run = datetime.now()

        p = subprocess.Popen(run_cmd, shell=True, stdout=writer, stderr=writer)

        while True:
            l = reader.readline()
            if l == "":
                continue
            print("out: " + l.strip())
            # are we done?
            if l.find(runargs.waitline) >= 0:
                end_run = datetime.now()
                run_elapsed = datetime.timestamp(end_run) - datetime.timestamp(
                    start_run
                )
                print("DONE")
                break
        print("Run time: %f s" % run_elapsed)

        if self.cleanup:
            self.clean_up(image_ref, container_name)

        return pull_elapsed, create_elapsed, run_elapsed

    def run_cmd_stdin(self, repo, runargs):
        image_ref = self.image_ref(repo)
        container_name = repo.replace(":", "-") + random_chars()

        pull_cmd = self.pull_cmd(image_ref)
        print(pull_cmd)

        print("Pulling image %s ..." % image_ref)
        with timer(pull_cmd) as t:
            pull_elapsed = t

        create_cmd = self.create_cmd_stdin_cmd(image_ref, container_name, runargs)
        print(create_cmd)

        print("Creating container for image %s ..." % image_ref)
        with timer(create_cmd) as t:
            create_elapsed = t

        run_cmd = self.task_start_cmd(container_name, iteration=True)
        print(run_cmd)

        print("Running container %s ..." % container_name)
        start_run = datetime.now()

        p = subprocess.Popen(
            run_cmd,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=sys.stdout,
            stderr=sys.stdout,
            bufsize=0,
        )

        print(runargs.stdin)
        stdin = runargs.stdin + "\nexit\n"
        p.communicate(stdin.encode())
        end_run = datetime.now()
        run_elapsed = datetime.timestamp(end_run) - datetime.timestamp(start_run)
        print("p.returncode:", p.returncode)
        # assert(p.returncode == 0)

        print("Run time: %f s" % run_elapsed)

        if self.cleanup:
            self.clean_up(image_ref, container_name)

        return pull_elapsed, create_elapsed, run_elapsed

    def run_cmd_url_wait(self, repo, runargs):
        image_ref = self.image_ref(repo)
        container_id = repo.replace(":", "-")

        pull_cmd = self.pull_cmd(image_ref)
        print(pull_cmd)

        print("Pulling image %s ..." % image_ref)
        with timer(pull_cmd) as t:
            pull_elapsed = t

        create_cmd = self.create_cmd_url_wait_cmd(image_ref, container_id, runargs)
        print(create_cmd)

        print("Creating container for image %s ..." % image_ref)
        with timer(create_cmd) as t:
            create_elapsed = t

        run_cmd = self.task_start_cmd(container_id, iteration=False)
        print(run_cmd)

        print("Running container %s ..." % container_id)
        start_run = datetime.now()

        p = subprocess.Popen(run_cmd, shell=True)
        while True:
            try:
                req = urllib.request.urlopen(runargs.waitURL)
                req.close()
                break
            except:
                time.sleep(0.01)  # wait 10ms
                pass  # retry

        end_run = datetime.now()
        run_elapsed = datetime.timestamp(end_run) - datetime.timestamp(start_run)

        print("Run time: %f s" % run_elapsed)

        if self.cleanup:
            self.clean_up(image_ref, container_id)

        return pull_elapsed, create_elapsed, run_elapsed

    def run(self, bench):
        repo = image_repo(bench.name)
        if repo in self.ECHO_HELLO:
            return self.run_echo_hello(repo=bench.name)
        elif repo in self.CMD_ARG:
            return self.run_cmd_arg(repo=bench.name, runargs=self.CMD_ARG[repo])
        elif repo in self.CMD_ARG_WAIT:
            return self.run_cmd_arg_wait(
                repo=bench.name, runargs=self.CMD_ARG_WAIT[repo]
            )
        elif repo in self.CMD_STDIN:
            return self.run_cmd_stdin(repo=bench.name, runargs=self.CMD_STDIN[repo])
        elif repo in self.CMD_URL_WAIT:
            return self.run_cmd_url_wait(
                repo=bench.name, runargs=self.CMD_URL_WAIT[repo]
            )
        else:
            print("Unknown bench: " + repo)
            exit(1)

    def pull_cmd(self, image_ref):
        insecure_flag = "--insecure-registry" if self.insecure_registry else ""
        return (
            f"nerdctl --snapshotter {self.snapshotter} pull {insecure_flag} {image_ref}"
        )

    def create_echo_hello_cmd(self, image_ref, container_id):
        return f"nerdctl --snapshotter {self.snapshotter} create --net=host --name={container_id} {image_ref} -- echo hello"

    def create_cmd_arg_cmd(self, image_ref, container_id, runargs):
        cmd = f"nerdctl --snapshotter {self.snapshotter} create --net=host "
        if len(runargs.env) > 0:
            env = " ".join(["--env %s=%s" % (k, v) for k, v in runargs.env.items()])
            cmd += f" {env} "
        for a, b in runargs.mount:
            a = os.path.join(os.path.dirname(os.path.abspath(__file__)), a)
            a = tmp_copy(a)
            cmd += f"--volume {a}:{b} "
        if len(runargs.runtime) > 0:
            cmd += f"--runtime {runargs.runtime} "
        if len(runargs.shmSize) > 0:
            cmd += f"--shm-size {runargs.shmSize} "
        if len(runargs.workDir) > 0:
            cmd += f"-w {runargs.workDir} "
        cmd += f"--name={container_id} {image_ref} "
        return cmd + runargs.arg

    def create_cmd_arg_wait_cmd(self, image_ref, container_id, runargs):
        cmd = f"nerdctl --snapshotter {self.snapshotter} create --net=host "
        if len(runargs.env) > 0:
            env = " ".join(["--env %s=%s" % (k, v) for k, v in runargs.env.items()])
            cmd += f" {env} "
        for a, b in runargs.mount:
            a = os.path.join(os.path.dirname(os.path.abspath(__file__)), a)
            a = tmp_copy(a)
            cmd += f"--volume {a}:{b} "
        cmd += f"--name={container_id} {image_ref} "
        if len(runargs.runtime) > 0:
            cmd += f"--runtime {runargs.runtime} "
        if len(runargs.shmSize) > 0:
            cmd += f"--shm-size {runargs.shmSize} "
        if len(runargs.workDir) > 0:
            cmd += f"-w {runargs.workDir} "
        if len(runargs.arg) > 0:
            cmd += f"{runargs.arg} "

        return cmd

    def create_cmd_stdin_cmd(self, image_ref, container_id, runargs):
        cmd = f"nerdctl --snapshotter {self.snapshotter} create --net=host "
        for a, b in runargs.mount:
            a = os.path.join(os.path.dirname(os.path.abspath(__file__)), a)
            a = tmp_copy(a)
            cmd += f"--volume {a}:{b} "
        cmd += f"--name={container_id} {image_ref} "
        if len(runargs.runtime) > 0:
            cmd += f"--runtime {runargs.runtime} "
        if len(runargs.shmSize) > 0:
            cmd += f"--shm-size {runargs.shmSize} "
        if len(runargs.workDir) > 0:
            cmd += f"-w {runargs.workDir} "
        if runargs.stdin_sh:
            cmd += f"-- {runargs.stdin_sh}"  # e.g., sh -c
        return cmd

    def create_cmd_url_wait_cmd(self, image_ref, container_id, runargs):
        cmd = f"nerdctl --snapshotter {self.snapshotter} create --net=host "
        for a, b in runargs.mount:
            a = os.path.join(os.path.dirname(os.path.abspath(__file__)), a)
            a = tmp_copy(a)
            cmd += f"--volume {a}:{b} "
        if len(runargs.env) > 0:
            env = " ".join([f"--env {k}={v}" for k, v in runargs.env.items()])
            cmd += f" {env} "
        if len(runargs.runtime) > 0:
            cmd += f"--runtime {runargs.runtime} "
        if len(runargs.shmSize) > 0:
            cmd += f"--shm-size {runargs.shmSize} "
        if len(runargs.workDir) > 0:
            cmd += f"-w {runargs.workDir} "
        cmd += f"--name={container_id} {image_ref} "
        if len(runargs.arg) > 0:
            cmd += f"{runargs.arg} "
        return cmd

    def task_start_cmd(self, container_id, iteration: bool):
        if iteration:
            return f"nerdctl --snapshotter {self.snapshotter} start -a {container_id}"
        else:
            return f"nerdctl --snapshotter {self.snapshotter} start {container_id}"

    def task_kill_cmd(self, container_id):
        return f"nerdctl --snapshotter {self.snapshotter} stop {container_id}"

    def clean_up(self, image_ref, container_id):
        print("Cleaning up environment for %s ..." % container_id)
        cmd = self.task_kill_cmd(container_id)
        print(cmd)
        rc = os.system(cmd)  # sometimes containers already exit. we ignore the failure.
        cmd = f"nerdctl --snapshotter {self.snapshotter} rm -f {container_id}"
        print(cmd)
        rc = os.system(cmd)
        assert rc == 0
        cmd = md = f"nerdctl --snapshotter {self.snapshotter} rmi -f {image_ref}"
        print(cmd)
        rc = os.system(cmd)
        assert rc == 0

    def pull(self, bench):
        cmd = f"{self.docker} pull {self.registry}{bench.name}"
        rc = os.system(cmd)
        assert rc == 0

    def push(self, bench):
        cmd = f"{self.docker} push {self.registry}{bench.name}"
        rc = os.system(cmd)
        assert rc == 0

    def tag(self, bench):
        cmd = "%s tag %s%s %s%s" % (
            self.docker,
            self.registry,
            bench.name,
            self.registry2,
            bench.name,
        )
        rc = os.system(cmd)
        assert rc == 0

    def operation(self, op, bench):
        if op == "run":
            return self.run(bench)
        elif op == "pull":
            self.pull(bench)
        elif op == "push":
            self.push(bench)
        elif op == "tag":
            self.tag(bench)
        else:
            print("Unknown operation: " + op)
            exit(1)


def image_repo(ref: str):
    return ref.split(":")[0]


def image_tag(ref: str) -> str:
    try:
        return ref.split(":")[1]
    except IndexError:
        return None


def main():
    benches = []
    kvargs = {"out": "bench"}

    parser = ArgumentParser()
    parser.add_argument(
        "--images",
        nargs="+",
        dest="images_list",
        type=str,
        default="",
    )

    parser.add_argument(
        "--engine",
        type=str,
        default="docker",
    )

    parser.add_argument(
        "--registry",
        type=str,
        default="",
    )

    parser.add_argument(
        "--registry2",
        type=str,
        default="",
    )

    parser.add_argument(
        "--all", dest="all_supported_images", action="store_true", required=False
    )

    parser.add_argument(
        "--op",
        type=str,
        choices=["run", "push", "pull", "tag"],
        default="pull",
    )

    parser.add_argument(
        "--snapshotter",
        type=str,
        help="only applied with containerd",
        choices=["overlayfs", "nydus", "stargz"],
        default="overlayfs",
    )

    parser.add_argument(
        "--tag",
        type=str,
        default="latest",
    )

    parser.add_argument(
        "--no-cleanup", dest="no_cleanup", action="store_true", required=False
    )
    parser.add_argument(
        "--insecure-registry",
        dest="insecure_registry",
        action="store_true",
        required=False,
    )

    parser.add_argument(
        "--bench-config",
        dest="bench_config",
        required=False,
        default="bench.yaml",
    )

    parser.add_argument(
        "--out-format",
        dest="output_format",
        type=str,
        choices=["csv", "json"],
        default="json",
    )

    parser.add_argument(
        "--bench-times",
        dest="bench_times",
        type=int,
        default=1,
    )

    args = parser.parse_args()

    op = args.op
    registry = args.registry
    registry2 = args.registry2
    docker = args.engine
    all_supported_images = args.all_supported_images
    images_list = args.images_list
    snapshotter = args.snapshotter
    cleanup = not args.no_cleanup
    insecure_registry = args.insecure_registry
    bench_config = args.bench_config

    runner = BenchRunner(
        docker=docker,
        registry=registry,
        registry2=registry2,
        snapshotter=snapshotter,
        cleanup=cleanup,
        insecure_registry=insecure_registry,
        bench_config=bench_config,
    )

    runner.load_bench_config()

    output_format = args.output_format
    bench_times = args.bench_times

    if all_supported_images:
        benches.extend(runner.ALL.values())
    else:
        for i in images_list:
            try:
                bench = copy.deepcopy(runner.ALL[image_repo(i)])

                tag = image_tag(i)
                if tag is not None:
                    bench.set_tag(tag)

                benches.append(bench)
            except KeyError:
                logging.warning("image %s not supported, skip", i)

    outpath = kvargs.pop("out")
    op = kvargs.pop("op", "run")
    f = open(outpath + "." + output_format, "w")

    if output_format == "csv":
        csv_headers = "timestamp,repo,bench,pull_elapsed(s),create_elapsed(s),run_elapsed(s),total_elapsed(s)"
        f.writelines(csv_headers + "\n")
        f.flush()

    for bench in benches:
        for _ in range(bench_times):
            pull_elapsed, create_elapsed, run_elapsed = runner.operation(op, bench)

            total_elapsed = f"{pull_elapsed + create_elapsed + run_elapsed: .6f}"
            timetamp = int(time.time() * 1000)
            pull_elapsed = f"{pull_elapsed: .6f}"
            create_elapsed = f"{create_elapsed: .6f}"
            run_elapsed = f"{run_elapsed: .6f}"

            if output_format == "json":
                row = {
                    "timestamp": timetamp,
                    "repo": bench.repo,
                    "bench": bench.name,
                    "pull_elapsed": pull_elapsed,
                    "create_elapsed": create_elapsed,
                    "run_elapsed": run_elapsed,
                    "total_elapsed": total_elapsed,
                }
                line = json.dumps(row)
            elif output_format == "csv":
                line = f"{timetamp},{bench.repo},{bench.name},{pull_elapsed},{create_elapsed},{run_elapsed},{total_elapsed}"

            print(line)
            f.writelines(line + "\n")
            f.flush()

    f.close()


if __name__ == "__main__":
    main()
    exit(0)
