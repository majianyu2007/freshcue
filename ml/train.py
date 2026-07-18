#!/usr/bin/env python3
"""FreshCue 时间角色分类模型训练脚手架（P2，未训练）。

只使用合成/脱敏数据；按模板划分 split 防泄漏；固定种子。
依赖（本仓库不 vendor）：pip install scikit-learn pandas onnx skl2onnx
"""
import argparse
import json
import random
from pathlib import Path

SEED = 42
LABELS = ["deadline", "event_start", "event_end", "departure",
          "expiry", "publish_time", "unknown"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="data/dataset.csv")
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--out", default="output/")
    args = parser.parse_args()
    random.seed(args.seed)

    data = Path(args.data)
    if not data.exists():
        raise SystemExit(
            f"数据集不存在：{data}。请先按 README 生成合成数据集，"
            "禁止使用真实用户截图。")

    # TODO(P2): 字符 n-gram TF-IDF + 线性分类器基线 → ONNX 导出。
    # 未实现前不产出任何指标数字（见 ml/README.md 红线）。
    raise SystemExit("训练流程尚未实现（P2）。当前产品使用规则基线。")


if __name__ == "__main__":
    main()
