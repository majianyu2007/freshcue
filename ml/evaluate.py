#!/usr/bin/env python3
"""评估脚手架：输出混淆矩阵与逐类 precision/recall/F1（P2，未实现）。"""
import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--data", default="data/dataset.csv")
    args = parser.parse_args()
    raise SystemExit("评估流程尚未实现（P2）。见 ml/README.md。")


if __name__ == "__main__":
    main()
