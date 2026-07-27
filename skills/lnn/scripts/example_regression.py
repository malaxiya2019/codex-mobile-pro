"""
LNN 回归示例 — 合成数据
用法: python example_regression.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lnn import create_lnn_regressor, train_lnn, evaluate_lnn
import numpy as np

def main():
    print("📈 LNN 回归示例")
    print("=" * 45)
    
    # 生成合成数据: y = 2*x1 - 1.5*x2 + sin(x3) + noise
    np.random.seed(42)
    n = 1000
    X = np.random.randn(n, 5)
    y = 2*X[:,0] - 1.5*X[:,1] + np.sin(X[:,2]) + np.random.randn(n)*0.1
    
    # 分割
    split1, split2 = int(n*0.7), int(n*0.85)
    X_train, y_train = X[:split1], y[:split1]
    X_val, y_val = X[split1:split2], y[split1:split2]
    X_test, y_test = X[split2:], y[split2:]
    
    # 归一化
    mean, std = X_train.mean(0), X_train.std(0)
    X_train = (X_train - mean) / std
    X_val = (X_val - mean) / std
    X_test = (X_test - mean) / std
    
    # 创建 LNN 回归器
    model = create_lnn_regressor(
        input_size=5,
        hidden_size=32,
        output_size=1,
        num_layers=3,
    )
    print(f"  LNN 参数: {sum(p.numel() for p in model.parameters()):,}")
    
    # 训练
    model, _, _ = train_lnn(model, X_train, y_train, X_val, y_val,
                            epochs=150, task='reg')
    
    # 评估
    preds, targets = evaluate_lnn(model, X_test, y_test)
    mse = ((preds - targets) ** 2).mean()
    r2 = 1 - ((targets - preds)**2).sum() / ((targets - targets.mean())**2).sum()
    print(f"\n  ✅ MSE: {mse:.4f}")
    print(f"  ✅ R² : {r2:.4f}")

if __name__ == '__main__':
    main()
