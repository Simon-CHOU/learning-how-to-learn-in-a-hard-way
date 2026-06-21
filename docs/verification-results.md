# 验证结果

## 验证环境

| 项目 | 值 |
|------|-----|
| TLC 版本 | 2.0 (2026.05.26.235334, rev 4ba7d88) |
| Java | 21.0.5 LTS |
| 搜索策略 | BFS（广度优先） |
| 状态数 | 67 distinct / 90 generated |
| 搜索深度 | 56 |
| 指纹碰撞概率 | 8.4×10⁻¹⁷ |

## 两项检查

### 1. TypeInvariant（类型不变式）— ✅ 始终通过

```tla
TypeInvariant ==
    /\ learnerState \in States
    /\ treeK2P \in [Knowledge -> [Pattern -> BOOLEAN]]
    /\ nodeMastery \in [AllNodes -> 0..100]
    /\ currentQuestion \in QuestionSet
```

这是一个**安全性质**（safety property）——"坏事永远不会发生"。它保证：

- `learnerState` 始终在五个合法状态之内，不会出现未定义的第七状态
- `treeK2P` 始终是一个合法的函数映射（Knowledge → Pattern → BOOLEAN），不会出现类型错误
- `nodeMastery` 始终在 [0, 100] 范围内，不会溢出
- `currentQuestion` 始终属于 QuestionSet，不会引用不存在的题目

类型不变式在初始状态成立，且每个 Next 动作都保持它。TLC 验证了在所有 67 个可达状态上此性质均成立。

### 2. EventuallyPassExam（活性性质）— ✅ 修复后通过

```tla
EventuallyPassExam == <>[] StrongEnough
```

这是一个**活性性质**（liveness property）——"好事最终会发生"。读作"最终总是 StrongEnough"，即存在某个未来时刻，从该时刻起 StrongEnough 持续成立。

#### 初次验证失败

首次运行 TLC 时，此性质被违反。反例轨迹如下：

```
State 1:  Idle,        mastery: k1=0,  k2=0,  p1=0,  e1=0
State 2:  Retrieving   (StartRetrieving)
State 3:  Expanding    (RetrieveFail — treeK2P 中无连接, relatedK={})
State 4:  Idle         (ExpandTree — 建立 K1→P1, K2→P1 连接)
State 5:  Retrieving
State 6:  Expanding    (RetrieveFail — mastery[K]=0 < 80)
State 7:  Idle         (ExpandTree — 弱节点强化, mastery+30)
State 8:  Retrieving
State 9:  Expanding    (RetrieveFail — mastery[K]=30 < 80)
State 10: Idle         (ExpandTree — 弱节点强化, mastery+30)
State 11: Retrieving
State 12: Expanding    (RetrieveFail — mastery[K]=60 < 80)
State 13: → STUTTERING FOREVER ←
```

**根因：** 系统在 State 12 进入 Expanding 状态后，`ExpandTree` 动作是 enabled 的（前置条件满足），但由于该动作没有弱公平性（Weak Fairness）约束，TLA+ 允许它**永远不执行**。系统可以在 Expanding 状态一直 stuttering（口吃步——变量不变但"时间"推进），StrongEnough 永远无法达成。

实际上只需再执行一次 ExpandTree，mastery 就会到达 90（≥80），RetrieveSuccess 就能触发，StrongEnough 就会成立。但没有公平性，这一步"可以不被迈出"。

#### 为什么 stuttering 是合法的

TLA+ 的规约公式 `[][Next]_Vars` 的含义是：

> 每一步，要么 Next 发生，要么 Vars 不变（stuttering）。

Stuttering 用于表达"系统可以不做任何事"，这是为了在精化（refinement）关系中允许高层规约跳过低层细节。但副作用是：如果没有公平性约束，任何状态都可以无限 stutter，即使 enabled 的动作也可以永远不执行。

#### 修复：补齐弱公平性

为所有内部状态迁移动作添加 `WF` 约束：

```tla
Spec == Init /\ [][Next]_Vars
          /\ WF_<<learnerState>>(StartRetrieving)
          /\ WF_<<learnerState>>(RetrieveSuccess)    -- 新增
          /\ WF_<<learnerState>>(RetrieveFail)       -- 新增
          /\ WF_<<learnerState>>(SolveCorrectly)     -- 新增
          /\ WF_<<learnerState>>(SolveIncorrectly)   -- 新增
          /\ WF_<<learnerState>>(Consolidate)        -- 新增
          /\ WF_<<learnerState>>(ExpandTree)         -- 新增
          /\ \A q \in QuestionSet : WF_<<currentQuestion>>(ChangeTo(q))
```

每个 `WF_<<learnerState>>(Action)` 的含义：

> 如果 Action 持续 enabled（即 learnerState 保持在对应值），则 Action 最终必须发生。

这覆盖了每个状态的唯一使能动作：
- Idle → StartRetrieving
- Retrieving → RetrieveSuccess 或 RetrieveFail
- Solving → SolveCorrectly 或 SolveIncorrectly
- Consolidating → Consolidate
- Expanding → ExpandTree

修复后重新运行 TLC：**Model checking completed. No error has been found.**

#### 为什么用 `<<learnerState>>` 而非 `Vars`

公平性条件的下标是"敏感变量"列表。`WF_<<learnerState>>(Action)` 表示：只要 `learnerState` 不变（即 Action 的使能条件持续成立），Action 就必须发生。

使用 `<<learnerState>>` 而非完整 `Vars` 的好处：
- 更精准：只要 learnerState 没变，就说明系统一直卡在这个状态
- 不会因为其他变量的变化（如 mastery 提升）而"重置"公平性计时

## 状态空间分析

### 状态图结构

67 个不同状态，出度分布：
- 最小出度：0（终态或 stuttering 状态）
- 最大出度：2（非确定性分支点，如 Solving → Consolidating/Expanding）
- 平均出度：1
- 95 分位出度：2

出度为 2 的状态出现在：
- **Solving 状态**：`SolveCorrectly` 和 `SolveIncorrectly` 同时 enabled（非确定性）
- **Expanding 状态**（relatedK 非空时）：强化弱节点分支和不变分支同时 enabled（当 weakK 为空且 weakE 为空时）

### 状态空间覆盖

广度优先搜索（BFS）穷举了所有可达状态，队列为空表示搜索完成。不存在未被探索的后继状态，验证是完备的（对给定的实例大小）。

## 与原始规范的等价性

两组验证入口产生相同的结果（67 states, 90 generated, depth 56）：

- `MC_bkxh_model.tla`（内联常量版）
- `MC_original.tla`（INSTANCE 包装版）

这确认了原始参数化规范在代入当前常量值后，与自包含版本逻辑等价。
