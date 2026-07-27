"""
Liquid Neural Network (LNN) — Liquid Time-Constant (LTC) 网络
==============================================================
基于 PyTorch 实现，支持分类和回归任务。

核心思想：
- 连续时间动力学 (Continuous-time dynamics)
- 可学习时间常数 τ (Learnable time constant tau)
- 自注意力机制 (Self-attention)
- 跳跃连接 + 层归一化

GitHub 来源: https://github.com/cserajdeep/LIQUID-NEURAL-NETWORK-LNN
"""
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset
import numpy as np


class LiquidTimeConstantCell(nn.Module):
    """
    液态时间常数 (LTC) 细胞单元
    
    微分方程: dh/dt = -h/τ + f(W_i·x + W_h·h)
    离散化: h_t = exp(-1/τ)·h_{t-1} + (1-exp(-1/τ))·f(W_i·x_t + W_h·h_{t-1})
    """
    def __init__(self, input_size: int, hidden_size: int, tau_init: float = 1.0):
        super().__init__()
        self.input_size = input_size
        self.hidden_size = hidden_size
        
        # 可学习时间常数 (核心创新)
        self.tau = nn.Parameter(torch.ones(hidden_size) * tau_init)
        
        # 输入投影
        self.input_proj = nn.Linear(input_size, hidden_size)
        # 循环权重 (隐状态)
        self.hidden_proj = nn.Linear(hidden_size, hidden_size)
        
        self.activation = nn.Tanh()
        self.dropout = nn.Dropout(0.2)

    def forward(self, x: torch.Tensor, hidden: torch.Tensor) -> torch.Tensor:
        input_term = self.input_proj(x)
        hidden_term = self.hidden_proj(hidden)
        
        # LTC 核心: 带时间常数的指数衰减
        decay = torch.exp(-1.0 / self.tau.abs())
        new_hidden = decay * hidden + (1 - decay) * self.activation(input_term + hidden_term)
        new_hidden = self.dropout(new_hidden)
        return new_hidden


class ImprovedLiquidNeuralNetwork(nn.Module):
    """
    改进型液态神经网络
    
    支持:
    - 多层 LTC 细胞
    - 多头自注意力
    - 跳跃连接
    - 层归一化
    - 分类/回归双模式
    """
    def __init__(
        self,
        input_size: int,
        hidden_size: int,
        output_size: int,
        num_layers: int = 2,
        task: str = 'cls',
        dropout: float = 0.2,
    ):
        super().__init__()
        self.task = task
        self.hidden_size = hidden_size
        self.num_layers = num_layers
        
        # 输入归一化
        self.input_norm = nn.BatchNorm1d(input_size)
        
        # 多层 LTC 细胞
        self.ltc_cells = nn.ModuleList()
        self.ltc_cells.append(LiquidTimeConstantCell(input_size, hidden_size))
        for _ in range(1, num_layers):
            self.ltc_cells.append(LiquidTimeConstantCell(hidden_size, hidden_size))
        
        # 多头自注意力 (捕捉时序关系)
        self.attention = nn.MultiheadAttention(hidden_size, num_heads=4, dropout=dropout)
        
        # 输出层 (带跳跃连接)
        self.pre_output = nn.Linear(hidden_size, hidden_size)
        self.output_layer = nn.Linear(hidden_size, output_size)
        
        self.dropout = nn.Dropout(dropout)
        self.layer_norm = nn.LayerNorm(hidden_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [batch, seq_len, input_size]
        batch_size, seq_len, _ = x.size()
        
        # 初始化隐状态
        device = x.device
        hidden_states = [
            torch.zeros(batch_size, self.hidden_size, device=device)
            for _ in range(self.num_layers)
        ]
        
        # 存储所有时间步输出 (给注意力层)
        seq_outputs = torch.zeros(seq_len, batch_size, self.hidden_size, device=device)
        
        for t in range(seq_len):
            x_t = x[:, t, :]
            if seq_len == 1:
                x_t = self.input_norm(x_t)
            
            # 逐层通过 LTC
            layer_input = x_t
            for i, cell in enumerate(self.ltc_cells):
                hidden_states[i] = cell(layer_input, hidden_states[i])
                layer_input = hidden_states[i]
            
            seq_outputs[t] = hidden_states[-1]
        
        # 自注意力
        attn_output, _ = self.attention(seq_outputs, seq_outputs, seq_outputs)
        
        # 跳跃连接 + 层归一化
        final_output = self.layer_norm(attn_output[-1] + hidden_states[-1])
        
        # 最终输出
        pre = F.relu(self.pre_output(final_output))
        pre = self.dropout(pre)
        out = self.output_layer(pre)
        
        if self.task == 'cls':
            out = F.log_softmax(out, dim=1)
        
        return out


# ════════════════════════════════════════════════════════════
# 训练工具
# ════════════════════════════════════════════════════════════

def create_dataloader(X, y, batch_size=32, shuffle=True):
    """创建 PyTorch DataLoader"""
    dataset = TensorDataset(
        torch.tensor(X, dtype=torch.float32),
        torch.tensor(y, dtype=torch.long if y.ndim == 1 else torch.float32),
    )
    return DataLoader(dataset, batch_size=batch_size, shuffle=shuffle)


def ensure_seq_dim(X):
    """确保数据有序列维度 [batch, seq_len, features]"""
    if isinstance(X, np.ndarray):
        if X.ndim == 2:
            return np.expand_dims(X, 1)
        return X
    # torch tensor
    if X.dim() == 2:
        return X.unsqueeze(1)
    return X


def train_lnn(
    model,
    X_train, y_train,
    X_val=None, y_val=None,
    epochs=200,
    lr=0.001,
    batch_size=32,
    patience=15,
    weight_decay=1e-5,
    verbose=True,
):
    """
    训练 LNN 模型
    
    参数:
        model: ImprovedLiquidNeuralNetwork 实例
        X_train, y_train: 训练数据
        X_val, y_val: 验证数据 (可选)
        epochs: 训练轮数
        lr: 学习率
        patience: 早停耐心值
        weight_decay: 权重衰减
        verbose: 是否打印日志
    
    返回:
        (model, train_losses, val_losses)
    """
    X_train = ensure_seq_dim(X_train)
    if X_val is not None:
        X_val = ensure_seq_dim(X_val)
    
    criterion = nn.NLLLoss() if model.task == 'cls' else nn.MSELoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, 'min', patience=8, factor=0.5)
    
    train_loader = create_dataloader(X_train, y_train, batch_size)
    val_loader = create_dataloader(X_val, y_val, batch_size, shuffle=False) if X_val is not None else None
    
    train_losses, val_losses = [], []
    best_loss = float('inf')
    best_epoch = 0
    stop_counter = 0
    
    for epoch in range(epochs):
        # ── 训练 ──
        model.train()
        total_loss = 0.0
        for bx, by in train_loader:
            optimizer.zero_grad()
            out = model(bx)
            loss = criterion(out, by)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            total_loss += loss.item()
        
        train_loss = total_loss / len(train_loader)
        train_losses.append(train_loss)
        
        # ── 验证 ──
        if val_loader is not None:
            model.eval()
            vloss = 0.0
            with torch.no_grad():
                for bx, by in val_loader:
                    out = model(bx)
                    vloss += criterion(out, by).item()
            val_loss = vloss / len(val_loader)
            val_losses.append(val_loss)
            scheduler.step(val_loss)
            
            if verbose and (epoch + 1) % 20 == 0:
                print(f"  Epoch {epoch+1:3d}/{epochs}  train={train_loss:.4f}  val={val_loss:.4f}")
            
            # 早停
            if val_loss < best_loss:
                best_loss = val_loss
                best_epoch = epoch
                stop_counter = 0
                torch.save(model.state_dict(), '/data/data/com.termux/files/home/.codex/skills/lnn/scripts/lnn_best.pth')
            else:
                stop_counter += 1
                if stop_counter >= patience:
                    if verbose:
                        print(f"  ⏹️  早停 @ epoch {epoch+1}, 最佳 epoch {best_epoch+1}")
                    model.load_state_dict(torch.load('/data/data/com.termux/files/home/.codex/skills/lnn/scripts/lnn_best.pth', weights_only=False))
                    break
        else:
            if verbose and (epoch + 1) % 20 == 0:
                print(f"  Epoch {epoch+1:3d}/{epochs}  train={train_loss:.4f}")
    
    return model, train_losses, val_losses


def evaluate_lnn(model, X_test, y_test):
    """评估 LNN 模型"""
    model.eval()
    X_test = ensure_seq_dim(X_test)
    loader = create_dataloader(X_test, y_test, batch_size=32, shuffle=False)
    
    all_preds, all_targets = [], []
    with torch.no_grad():
        for bx, by in loader:
            out = model(bx)
            if model.task == 'cls':
                _, preds = torch.max(out, 1)
                all_preds.extend(preds.numpy())
                all_targets.extend(by.numpy())
            else:
                all_preds.extend(out.squeeze().numpy())
                all_targets.extend(by.squeeze().numpy())
    
    return np.array(all_preds), np.array(all_targets)


def predict_lnn(model, X):
    """对新数据进行预测"""
    model.eval()
    X = ensure_seq_dim(X)
    if isinstance(X, np.ndarray):
        X = torch.tensor(X, dtype=torch.float32)
    with torch.no_grad():
        out = model(X)
        if model.task == 'cls':
            _, preds = torch.max(out, 1)
            return preds.numpy()
        return out.squeeze().numpy()


def create_lnn_classifier(
    input_size,
    hidden_size=32,
    output_size=None,
    num_layers=2,
    dropout=0.2,
):
    """快速创建 LNN 分类器"""
    return ImprovedLiquidNeuralNetwork(
        input_size=input_size,
        hidden_size=hidden_size,
        output_size=output_size or 2,
        num_layers=num_layers,
        task='cls',
        dropout=dropout,
    )


def create_lnn_regressor(
    input_size,
    hidden_size=32,
    output_size=1,
    num_layers=2,
    dropout=0.2,
):
    """快速创建 LNN 回归器"""
    return ImprovedLiquidNeuralNetwork(
        input_size=input_size,
        hidden_size=hidden_size,
        output_size=output_size,
        num_layers=num_layers,
        task='reg',
        dropout=dropout,
    )
