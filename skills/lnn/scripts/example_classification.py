"""
LNN 分类示例 — Iris 数据集
用法: python example_classification.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lnn import create_lnn_classifier, train_lnn, evaluate_lnn
import numpy as np
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, confusion_matrix

def main():
    print("🌺 LNN Iris 分类示例")
    print("=" * 45)
    
    # 加载数据
    iris = load_iris()
    X, y = iris.data, iris.target
    print(f"  样本: {X.shape[0]}  特征: {X.shape[1]}  类别: {len(np.unique(y))}")
    
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    X_train, X_val, y_train, y_val = train_test_split(X_train, y_train, test_size=0.2, random_state=42)
    
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_val = scaler.transform(X_val)
    X_test = scaler.transform(X_test)
    
    # 创建 LNN
    model = create_lnn_classifier(
        input_size=4,
        hidden_size=16,
        output_size=3,
        num_layers=2,
    )
    print(f"  LNN 参数: {sum(p.numel() for p in model.parameters()):,}")
    
    # 训练
    model, losses, _ = train_lnn(model, X_train, y_train, X_val, y_val, epochs=100)
    
    # 评估
    preds, targets = evaluate_lnn(model, X_test, y_test)
    acc = accuracy_score(targets, preds)
    print(f"\n  ✅ 测试准确率: {acc:.4f} ({acc*100:.1f}%)")
    print(f"\n  混淆矩阵:")
    print(confusion_matrix(targets, preds))
    
    # 预测新样本
    sample = scaler.transform([[5.1, 3.5, 1.4, 0.2]])
    pred = model.predict(sample)
    print(f"\n  🔮 预测 [5.1,3.5,1.4,0.2] → {iris.target_names[pred[0]]}")

if __name__ == '__main__':
    main()
