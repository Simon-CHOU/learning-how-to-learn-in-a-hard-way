# 约束与扩展方向

## 当前约束

### 1. 小模型实例

当前验证实例的规模：

| 维度 | 当前值 | 最小合法值 |
|------|--------|-----------|
| Knowledge | 2 | 2 |
| Pattern | 1 | 1 |
| ErrorPoint | 1 | 1 |
| QuestionSet | 1 | 1 |

状态空间为 67 个不同状态。增大任一维度都会导致状态空间膨胀。

**影响：** 无法验证大规模实例下是否有未预见的交互——例如多 Pattern 共享 Knowledge 节点时，Consolidate 对共享节点的 mastery 提升是否产生非预期的级联效应。

### 2. 单题目

`QuestionSet = {Q1}`，所有题目映射到同一个 Pattern。在多题目场景中：
- 不同题目可能映射到不同 Pattern
- ChangeTo 的非确定性分支会被探索
- 题目顺序可能影响学习路径

### 3. 确定性阈值

`MasteryThreshold = 80` 作为常量固定。原始规范中它虽然是 CONSTANTS 但 ASSUME 约束为 80。不同阈值（如 60 或 95）会影响：
- 进入 Solving 所需的 ExpandTree 循环次数
- StrongEnough 的达成难度
- 收敛保证是否仍然成立

### 4. 无遗忘机制

mastery 单调递增且永久保持。真实认知中：
- 长期不复习会导致 mastery 衰减
- 干扰效应（新知识覆盖旧知识）
- 疲劳效应

### 5. 无并发

模型是单线程认知过程。不涉及：
- 多题目交替处理
- 多 Pattern 并行检索
- 知识迁移（从一个 Pattern 学到的自动应用到相关 Pattern）

### 6. 无概率模型

Solving 的答对/答错是非确定性分支（TLC 探索两者），但没有概率权重。无法表达"mastery 越高，答对概率越大"的渐进关系。

### 7. 常量定义的工程限制

原始规范使用 CONSTANTS 声明参数，但 TLC 的 `.cfg` 文件不支持函数类型常量。当前通过 `.tla` 包装文件（INSTANCE 或内联）绕过。这使得：
- 无法用同一 cfg 文件切换不同常量组合
- 每次切换常量需编辑 `.tla` 文件

## 扩展方向

### 短期：扩大实例验证

**目标：** 用 3-5 个 Knowledge、2-3 个 Pattern 验证同一规范。

**改动点：**
```tla
-- MC_bkxh_model.tla
K3 == "k3"
K4 == "k4"
P2 == "p2"
E2 == "e2"
Q2 == "q2"

Knowledge == {K1, K2, K3, K4}
Pattern == {P1, P2}
ErrorPoint == {E1, E2}
QuestionSet == {Q1, Q2}
QuestionPatternMap == [Q1 |-> P1, Q2 |-> P2]
PatternInherentErrors == [P1 |-> {E1}, P2 |-> {E2}]
```

**预期影响：** 状态空间从 67 增长到数百或数千。需关注 TLC 内存和运行时间。

### 中期：多题目交错调度

**目标：** 验证多题目交替出现时，ChangeTo 的公平性是否保证所有题目最终都被"学会"。

**需添加的性质：**
```tla
EachQuestionEventuallyMastered ==
    \A q \in QuestionSet :
        <>[](LET p == QuestionPatternMap[q] IN
             ... p 的关联节点全部达标 ...)
```

### 中期：遗忘机制

**目标：** 引入 mastery 衰减，验证活性性质是否仍保持。

**设计选项：**

A) **周期性衰减**：每个完整周期后所有 mastery 衰减 5 点
```tla
Decay ==
    /\ nodeMastery' = [n \in AllNodes |-> MAX(nodeMastery[n] - 5, 0)]
    /\ UNCHANGED <<learnerState, treeK2P, currentQuestion>>
```

B) **基于时间的衰减**：未被访问的节点衰减更快
```tla
DecayUnvisited == ...
```

**挑战：** 衰减+提升可能形成振荡，`<>[]StrongEnough` 可能不再成立。可能需要改用更弱的性质如 `[]<>StrongEnough`（无限频繁地掌握）或 `<>StrongEnough`（至少掌握一次）。

### 中期：知识迁移

**目标：** 当一个 Knowledge 节点在一个 Pattern 上达到 mastery 阈值后，自动建立它到其他相关 Pattern 的连接。

**设计：**
```tla
KnowledgeTransfer ==
    \E p1, p2 \in Pattern : p1 # p2
        /\ LET sharedK == {k \in Knowledge :
               treeK2P[k][p1] = TRUE /\ nodeMastery[k] >= 80}
           IN treeK2P' = [k \in Knowledge |->
               IF k \in sharedK
               THEN [treeK2P[k] EXCEPT ![p2] = TRUE]
               ELSE treeK2P[k]]
```

### 长期：概率 TLC (ProbTLC)

**目标：** 将 Solving 的非确定性替换为概率分布，分析不同策略的收敛概率。

```tla
-- 概率版本
SolveCorrectly_p ==
    /\ learnerState = "Solving"
    /\ LET p_correct == mastery / 100  -- 掌握度越高，正确率越高
       IN ... -- 概率分支
```

需要使用 ProbTLC（TLC 的概率扩展），不在标准 tla2tools.jar 中。

### 长期：精化链

**目标：** 建立从高层认知规约到底层实现的状态机精化链。

```
AbstractCognitiveSpec
    ↓ (refinement mapping)
ConcreteLearningAlgorithm
    ↓ (refinement mapping)
Implementation (Python/JS)
```

TLA+ 的精化（refinement）机制可以保证低层实现不引入高层规约未允许的行为。

## 规模估算

| Knowledge | Pattern | ErrorPoint | 估算状态数 | TLC 耗时（估算） |
|-----------|---------|------------|-----------|-----------------|
| 2 | 1 | 1 | 67 | < 1s |
| 3 | 1 | 1 | ~200 | < 1s |
| 4 | 2 | 2 | ~2,000 | ~1s |
| 5 | 3 | 3 | ~50,000 | ~10s |
| 10 | 5 | 5 | ~10⁷ | ~10min |
| 20 | 10 | 10 | ~10¹² | 不可行（需符号模型检验） |

当状态空间超过 10⁸ 时，显式状态模型检验（TLC 的默认模式）将不可行。届时需考虑：
- **符号模型检验**（基于 BDD）
- **定理证明**（TLAPS — TLA+ Proof System）
- **Apalache**（基于 SMT 的 TLA+ 模型检验器）
