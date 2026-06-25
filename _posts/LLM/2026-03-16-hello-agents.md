---
layout: post
title: "hello-agents笔记"
date: 2026-03-16
description: "hello-agents项目记录"
tag: LLM
---

# 大语言模型基础

## 1. 从 N-gram 到 RNN

- 统计语言模型
一个句子出现的概率，等于该句子中每个词出现的条件概率的连乘：

$$
\begin{aligned}
P(S) &= P(w_1,w_2,\ldots,w_m) \\
&= P(w_1)\cdot P(w_2\mid w_1)\cdot P(w_3\mid w_1,w_2)\cdots P(w_m\mid w_1,\ldots,w_{m-1})
\end{aligned}
$$

- N-gram（数据稀疏性；泛化能力差）
Trigram (当 N=3 时) ：假设一个词的出现只与它前面的两个词有关：

$$
P(w_i\mid w_1,\ldots,w_{i-1})\approx P(w_i\mid w_{i-2},w_{i-1})
$$

考虑一个仅包含以下两句话的迷你语料库：datawhale agent learns, datawhale agent works
```python
import collections

# 示例语料库，与上方案例讲解中的语料库保持一致
corpus = "datawhale agent learns datawhale agent works"
tokens = corpus.split()
total_tokens = len(tokens)

# --- 第一步:计算 P(datawhale) ---
count_datawhale = tokens.count('datawhale')
p_datawhale = count_datawhale / total_tokens
print(f"第一步: P(datawhale) = {count_datawhale}/{total_tokens} = {p_datawhale:.3f}")

# --- 第二步:计算 P(agent|datawhale) ---
# 先计算 bigrams 用于后续步骤
bigrams = zip(tokens, tokens[1:])
bigram_counts = collections.Counter(bigrams)
count_datawhale_agent = bigram_counts[('datawhale', 'agent')]
# count_datawhale 已在第一步计算
p_agent_given_datawhale = count_datawhale_agent / count_datawhale
print(f"第二步: P(agent|datawhale) = {count_datawhale_agent}/{count_datawhale} = {p_agent_given_datawhale:.3f}")

# --- 第三步:计算 P(learns|agent) ---
count_agent_learns = bigram_counts[('agent', 'learns')]
count_agent = tokens.count('agent')
p_learns_given_agent = count_agent_learns / count_agent
print(f"第三步: P(learns|agent) = {count_agent_learns}/{count_agent} = {p_learns_given_agent:.3f}")

# --- 最后:将概率连乘 ---
p_sentence = p_datawhale * p_agent_given_datawhale * p_learns_given_agent
print(f"最后: P('datawhale agent learns') ≈ {p_datawhale:.3f} * {p_agent_given_datawhale:.3f} * {p_learns_given_agent:.3f} = {p_sentence:.3f}")
```

输出：

```text
第一步: P(datawhale) = 2/6 = 0.333
第二步: P(agent|datawhale) = 2/2 = 1.000
第三步: P(learns|agent) = 1/2 = 0.500
最后: P('datawhale agent learns') ≈ 0.333 * 1.000 * 0.500 = 0.167
```

- 神经网络语言模型与词嵌入
余弦相似度 ，它通过计算两个词向量夹角的余弦值来衡量它们的相似性。
例子：`vector('King') - vector('Man') + vector('Woman') `这个向量运算的结果，在向量空间中与 `vector('Queen')`相似。

```python
import numpy as np

# 假设我们已经学习到了简化的二维词向量
embeddings = {
    "king": np.array([0.9, 0.8]),
    "queen": np.array([0.9, 0.2]),
    "man": np.array([0.7, 0.9]),
    "woman": np.array([0.7, 0.3])
}

def cosine_similarity(vec1, vec2):
    dot_product = np.dot(vec1, vec2)
    norm_product = np.linalg.norm(vec1) * np.linalg.norm(vec2)
    return dot_product / norm_product

# king - man + woman
result_vec = embeddings["king"] - embeddings["man"] + embeddings["woman"]

# 计算结果向量与 "queen" 的相似度
sim = cosine_similarity(result_vec, embeddings["queen"])

print(f"king - man + woman 的结果向量: {result_vec}")
print(f"该结果与 'queen' 的相似度: {sim:.4f}")
```

输出：

```text
king - man + woman 的结果向量: [0.9 0.2]
该结果与 'queen' 的相似度: 1.0000
```

具体用到的步骤：
1. 词从随机向量变成有语义的向量
```python
import numpy as np
from gensim.models import Word2Vec
import warnings

warnings.filterwarnings('ignore')

# 极简语料（只保留核心语义）
corpus = [
    ["king", "male", "monarch"],
    ["queen", "female", "monarch"],
    ["man", "male", "person"],
    ["woman", "female", "person"]
]

# 1. 初始化模型（vector_size=2，简化为2维，方便观察）
model = Word2Vec(vector_size=2, window=3, min_count=1, sg=0, epochs=100)

# 2. 看训练前的向量（空的，报错）
print("=== 训练前：model.wv为空 ===")
try:
    print(model.wv["king"])
except KeyError:
    print("无king的向量，因为还没训练")

# 3. 训练模型（填充向量）
model.build_vocab(corpus)  # 步骤1：编序号
print("\n=== 训练中：先给单词分配随机初始向量 ===")
# 手动查看king的初始向量（训练前的随机值）
init_king_vec = model.wv.vectors[model.wv.key_to_index["king"]]
print(f"king的初始随机向量：{init_king_vec.round(2)}")

model.train(corpus, total_examples=model.corpus_count, epochs=model.epochs)  # 步骤2-3：训练调整

# 4. 训练后：查看最终向量
print("\n=== 训练后：有语义的向量 ===")
for word in ["king", "queen", "man", "woman"]:
    vec = model.wv[word].round(2)
    print(f"{word}: {vec}")
```

2. 学习 + 降维到二维词向量
```python
import numpy as np
from gensim.models import Word2Vec
from sklearn.decomposition import PCA
import warnings
warnings.filterwarnings('ignore')  # 忽略无关警告

# ---------------------- 1. 准备极小语料库 ----------------------
# 语料库：由多个句子组成（每个句子是单词列表），包含king/queen/man/woman的语义关联
corpus = [
    ["king", "is", "a", "male", "monarch"],
    ["queen", "is", "a", "female", "monarch"],
    ["man", "is", "a", "male", "person"],
    ["woman", "is", "a", "female", "person"],
    ["king", "rules", "the", "kingdom"],
    ["queen", "rules", "the", "kingdom"],
    ["man", "works", "in", "the", "city"],
    ["woman", "works", "in", "the", "city"]
]

# ---------------------- 2. 用Word2Vec学习高维词向量 ----------------------
# 训练Word2Vec模型（默认学习100维向量，min_count=1表示保留所有出现过的单词）
model = Word2Vec(
    sentences=corpus,  # 输入语料
    vector_size=100,   # 高维向量维度（默认100）
    window=3,          # 上下文窗口大小（看前后3个词）
    min_count=1,       # 最少出现次数（1表示不过滤）
    sg=0               # 用CBOW算法（新手不用纠结，默认即可）
)

# 获取高维词向量（100维）
high_dim_vectors = {
    word: model.wv[word] 
    for word in ["king", "queen", "man", "woman"]
}
print("=== 100维高维词向量（仅展示前5维） ===")
for word, vec in high_dim_vectors.items():
    print(f"{word}: {vec[:5]}")  # 只打印前5维，避免输出过长

# ---------------------- 3. 用PCA将高维向量降维到2维 ----------------------
# 提取高维向量矩阵（按顺序排列单词）
words = ["king", "queen", "man", "woman"]
high_dim_matrix = np.array([high_dim_vectors[word] for word in words])

# 初始化PCA，降维到2维
pca = PCA(n_components=2)
# 训练PCA并转换向量
two_dim_vectors = pca.fit_transform(high_dim_matrix)

# 整理成字典（最终的二维词向量）
two_dim_embeddings = {
    word: two_dim_vectors[i] 
    for i, word in enumerate(words)
}

# ---------------------- 4. 输出最终的二维词向量 ----------------------
print("\n=== 降维后的二维词向量 ===")
for word, vec in two_dim_embeddings.items():
    # 保留2位小数，让结果更整洁
    print(f"{word}: [{vec[0]:.2f}, {vec[1]:.2f}]")

# ---------------------- 5. 验证语义算术（可选） ----------------------
# 计算 king - man + woman
king_vec = two_dim_embeddings["king"]
man_vec = two_dim_embeddings["man"]
woman_vec = two_dim_embeddings["woman"]
result_vec = king_vec - man_vec + woman_vec

# 计算结果向量与queen的余弦相似度（复用之前的函数）
def cosine_similarity(vec1, vec2):
    dot_product = np.dot(vec1, vec2)
    norm_product = np.linalg.norm(vec1) * np.linalg.norm(vec2)
    return dot_product / norm_product

sim = cosine_similarity(result_vec, two_dim_embeddings["queen"])
print(f"\n=== 语义验证 ===")
print(f"king - man + woman 的二维向量: [{result_vec[0]:.2f}, {result_vec[1]:.2f}]")
print(f"与queen的余弦相似度: {sim:.4f}")
```

