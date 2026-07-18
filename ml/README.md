# ml/ — 端侧时间语义模型（P2，未阻塞 P0）

状态：**脚手架，未训练**。P0 使用 `RuleBasedTemporalSemanticClassifier`
（即 lib/domain/parser/role_classifier.dart 的规则评分），已通过 62 项解析测试。

## 目标

`TemporalSemanticClassifier` 接口（时间角色 / 卡片分类）的 MindSpore Lite
实现，低置信度时回退规则（Hybrid）。

## 数据

`data/dataset.csv`：`text,label,source,split`。**只允许合成或明确脱敏样本**；
train/val/test 不得共享模板（脚本按模板 ID 划分，避免虚高）。

## 复现流程（取得环境后）

```bash
python3 train.py --data data/dataset.csv --seed 42 --out output/
python3 evaluate.py --model output/model.onnx --data data/dataset.csv
# 输出混淆矩阵与逐类 precision/recall/F1 至 output/metrics.json
# ONNX → MindSpore Lite（记录完整命令与版本）：
# converter_lite --fmk=ONNX --modelFile=output/model.onnx --outputFile=output/model
```

## 红线

- 不提交来源不明的预训练权重；
- 未实际训练评估前不得在任何文档写准确率数字；
- 固定随机种子；保存标签表与预处理配置随模型版本。
