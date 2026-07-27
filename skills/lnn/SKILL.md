---
name: lnn
description: "Liquid Neural Network (LNN/LTC) — 液态时间常数神经网络，用于分类和回归任务。使用 Liquid Time-Constant (LTC) 网络，支持可学习时间常数、自注意力机制、多层结构。"
---

# Liquid Neural Network (LNN) Skill

## 概述
将 **液态时间常数网络 (Liquid Time-Constant / LTC)** 集成到 Codex 中，用于分类和回归任务。

**来源:** https://github.com/cserajdeep/LIQUID-NEURAL-NETWORK-LNN

## 核心创新
- **可学习时间常数 τ** — 网络自动学习信息保留/遗忘的速率
- **连续时间动力学** — dh/dt = -h/τ + f(W·x + W·h)
- **自注意力机制** — 多头注意力捕捉时序依赖
- **跳跃连接 + 层归一化** — 稳定深层网络训练

## 何时使用
用户提到以下关键词时使用本技能：
- "液态神经网络"、"LNN"、"LTC"、"液体神经网络"
- "时间常数"、"连续时间"、"liquid neural network"
- "用神经网络分类"、"用神经网络回归"
- 用户需要 ML 分类/回归但传统模型效果不佳

## Python API 速查

```python
from lnn import (
    create_lnn_classifier,
    create_lnn_regressor,
    train_lnn,
    evaluate_lnn,
    predict_lnn,
    ImprovedLiquidNeuralNetwork,
)

# 分类
model = create_lnn_classifier(input_size=4, hidden_size=16, output_size=3)
model, losses, _ = train_lnn(model, X_train, y_train, X_val, y_val, epochs=200)
preds, targets = evaluate_lnn(model, X_test, y_test)

# 回归
model = create_lnn_regressor(input_size=5, hidden_size=32, output_size=1)
model, losses, _ = train_lnn(model, X_train, y_train, X_val, y_val, epochs=200)
preds, targets = evaluate_lnn(model, X_test, y_test)

# 预测
predictions = predict_lnn(model, X_new)
```

## 文件结构
```
~/.codex/skills/lnn/
├── SKILL.md
├── .codex-plugin/plugin.json
└── scripts/
    ├── lnn.py
    ├── example_classification.py
    └── example_regression.py
```

## 环境要求
- Python 3.8+
- PyTorch (已安装: torch 2.11.0)
- NumPy (已安装: numpy 2.4.4)
- scikit-learn (可选, 用于加载演示数据集)
