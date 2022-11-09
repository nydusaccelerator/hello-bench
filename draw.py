#!/usr/local/bin/python3

import os
import json
import pandas as pd
import shutil
import matplotlib.pyplot as plt
from pandas.api.types import CategoricalDtype
import argparse

parser = argparse.ArgumentParser(
    description="Handle data of hello bench to csv and png"
)
parser.add_argument(
    "-d", type=str, default="data", help="data directory", required=True
)
parser.add_argument(
    "-r", type=str, default="result", help="result directory", required=True
)
args = parser.parse_args()

data_dir = args.d
result_dir = args.r
sub_data_dir = "csv"
sub_picture_dir = "png"

print("data_dir: %s, result_dir: %s" % (data_dir, result_dir))


def to_csv():
    average_list = []
    for current_dir, _, file_list in os.walk(data_dir):
        for filename in file_list:
            filename_path = os.path.join(current_dir, filename)
            print("file: ", filename_path)
            with open(filename_path) as f:
                for line in f.readlines():
                    if line.strip() != "":
                        json_line = json.loads(line)
                        image = json_line["bench"]
                        pull_time = json_line["pull_time"]
                        create_time = json_line["create_time"]
                        run_time = json_line["run_time"]

                        average_list.append(
                            {
                                "image": image,
                                "pull": pull_time,
                                "create": create_time,
                                "run": run_time,
                            }
                        )

    average_df = pd.DataFrame(average_list)

    all_data = dict()
    for image, data in average_df.groupby("image"):
        single_data = [
            {
                "image": image,
                "type": "pull",
                "mean": data["pull"].mean(),
                "p25": data["pull"].quantile(0.25),
                "p50": data["pull"].quantile(0.5),
                "p75": data["pull"].quantile(0.75),
                "p90": data["pull"].quantile(0.90),
                "p95": data["pull"].quantile(0.95),
                "p99": data["pull"].quantile(0.99),
                "p100": data["pull"].quantile(1),
            },
            {
                "image": image,
                "type": "create",
                "mean": data["create"].mean(),
                "p25": data["create"].quantile(0.25),
                "p50": data["create"].quantile(0.5),
                "p75": data["create"].quantile(0.75),
                "p90": data["create"].quantile(0.90),
                "p95": data["create"].quantile(0.95),
                "p99": data["create"].quantile(0.99),
                "p100": data["create"].quantile(1),
            },
            {
                "image": image,
                "type": "run",
                "mean": data["run"].mean(),
                "p25": data["run"].quantile(0.25),
                "p50": data["run"].quantile(0.5),
                "p75": data["run"].quantile(0.75),
                "p90": data["run"].quantile(0.90),
                "p95": data["run"].quantile(0.95),
                "p99": data["run"].quantile(0.99),
                "p100": data["run"].quantile(1),
            },
        ]

        image_name = image.split(":")[0]
        if image_name in all_data.keys():
            all_data[image_name] = all_data[image_name] + single_data
        else:
            all_data[image_name] = single_data

    if os.path.exists(result_dir):
        shutil.rmtree(result_dir, ignore_errors=True)
    os.mkdir(result_dir)
    os.mkdir(os.path.join(result_dir, "/", sub_data_dir))
    os.mkdir(os.path.join(result_dir, "/", sub_picture_dir))

    type_order = CategoricalDtype(["pull", "create", "run"], ordered=True)
    all_data_pd_line = []

    for key in all_data:
        data_pd = pd.DataFrame(all_data[key])
        data_pd["type"] = data_pd["type"].astype(type_order)
        data_pd.sort_values(by="type", inplace=True, ascending=True)
        print(key, data_pd)
        data_pd.to_csv(os.path.join(result_dir, "/", sub_data_dir, "/", key, ".csv"))

        for image_name, image_data in data_pd.groupby("image"):
            all_data_pd_line = all_data_pd_line + [
                {
                    "image": image_name,
                    "pull": image_data[image_data["type"] == "pull"]["mean"].mean(),
                    "create": image_data[image_data["type"] == "create"]["mean"].mean(),
                    "run": image_data[image_data["type"] == "run"]["mean"].mean(),
                }
            ]
    all_data_pd = pd.DataFrame(all_data_pd_line)
    all_data_pd.to_csv(os.path.join(result_dir, "/", "all_mean.csv"))


def draw():
    if os.path.exists(os.path.join(result_dir, "/", sub_picture_dir)):
        shutil.rmtree(
            os.path.join(result_dir, "/", sub_picture_dir), ignore_errors=True
        )
    os.mkdir(os.path.join(result_dir, "/", sub_picture_dir))
    for current_dir, _, file_list in os.walk(
        os.path.join(result_dir, "/", sub_data_dir)
    ):
        for filename in file_list:
            filename_path = os.path.join(current_dir, filename)
            print("file: ", filename_path)
            data_pd = pd.read_csv(filename_path)
            print(data_pd)

            for index, data_series in data_pd.iterrows():
                picture_path = os.path.join(
                    result_dir,
                    "/",
                    sub_picture_dir,
                    "/",
                    data_series["image"].split(":")[0],
                )
                if not os.path.exists(picture_path):
                    os.mkdir(picture_path)

                x = ["mean", "p25", "p50", "p75", "p90", "p95", "p99", "p100"]
                y = data_series.to_frame().values.T[0][3:]
                data = pd.DataFrame(
                    {
                        "type": x,
                        "data": y,
                    }
                )
                print(data)
                data.plot(
                    kind="bar",
                    x="type",
                    rot=0,
                    title="image: "
                    + data_series["image"]
                    + "  ("
                    + data_series["type"]
                    + ")",
                    legend=False,
                )
                plt.xlabel(None)
                plt.subplots_adjust(left=0.1, bottom=0.1, right=0.9, top=0.9)
                plt.savefig(
                    os.path.join(
                        picture_path,
                        "/",
                        data_series["image"].replace(":", "-"),
                        "_",
                        data_series["type"],
                        ".png",
                    )
                )


def draw_all():
    all_data_pd = pd.read_csv(
        os.path.join(result_dir, "/", "all_mean.csv"), index_col=0
    )

    print(all_data_pd)
    all_data = dict()
    for image, data in all_data_pd.groupby("image"):
        single_data = [
            {
                "image": image,
                "pull": data["pull"].mean(),
                "create": data["create"].mean(),
                "run": data["run"].mean(),
            }
        ]

        image_name = image.split(":")[0]
        if image_name in all_data.keys():
            all_data[image_name] = all_data[image_name] + single_data
        else:
            all_data[image_name] = single_data

    for key in all_data:
        data_pd = pd.DataFrame(all_data[key])
        fig, ax = plt.subplots()
        print(data_pd)
        ax.bar(data_pd["image"], data_pd["pull"], label="pull")
        ax.bar(
            data_pd["image"], data_pd["create"], bottom=data_pd["pull"], label="create"
        )
        ax.bar(
            data_pd["image"],
            data_pd["run"],
            bottom=data_pd["pull"] + data_pd["create"],
            label="run",
        )

        ax.legend(bbox_to_anchor=(1.26, 1))
        plt.subplots_adjust(left=0.12, bottom=0.32, right=0.798, top=0.88)
        plt.xticks(rotation=45)
        plt.ylabel("time(s)")
        plt.savefig(os.path.join(result_dir, "/", key, ".png"))


if __name__ == "__main__":
    to_csv()
    draw()
    draw_all()
