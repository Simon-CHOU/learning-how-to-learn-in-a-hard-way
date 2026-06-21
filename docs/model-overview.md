# 模型概览

## 什么是思维树认知架构

这个 TLA+ 规范形式化了一个基于 **思维树（MindTree）** 方法论的认知过程模型。核心思想是：人类解题时的认知活动可以抽象为一棵由三类节点构成的思维树，学习过程就是在这棵树上建立连接并提升节点"掌握度"的过程。

## 三类节点

```
Knowledge ────── treeK2P ──────→ Pattern ────── PatternInherentErrors ──────→ ErrorPoint
  (知识点)         (映射)          (模式)              (固有错误映射)              (易错点)
```

### Knowledge（知识节点）

构成认知基础的最小单元。例如：一条语法规则、一个数学公式、一个概念定义。

在模型中，Knowledge 节点通过 `treeK2P` 矩阵与 Pattern 节点建立连接。初始状态下所有连接为 `FALSE`——知识点尚未与任何题型模式关联。

**ASSUME 约束：** `Cardinality(Knowledge) >= 2`，即至少需要两个知识点，因为 ExpandTree 的新建连接分支需要选择两个不同的 Knowledge 节点。

### Pattern（模式节点）

代表一道题或一类题的"解题套路"。它是连接 Knowledge 和 ErrorPoint 的枢纽：一道题对应一个 Pattern，通过它找到需要的知识点和容易犯的错误。

`QuestionPatternMap` 将每道考题映射到它的 Pattern。在模型中，所有 Pattern 构成了考试可能覆盖的范围（`ExamPatterns`）。

### ErrorPoint（易错点）

每类题型固有的易犯错误。例如：做矩阵乘法时容易搞混行列顺序、写递归时忘记 base case。

`PatternInherentErrors` 将每个 Pattern 映射到它固有的一组 ErrorPoint。**ASSUME 约束：** 每个 Pattern 至少关联一个 ErrorPoint（非空），保证每道题都有"陷阱"需要克服。

### 节点的数学表示

```tla
AllNodes == Knowledge \cup Pattern \cup ErrorPoint
```

三类节点互不相交（由 ASSUME 保证两两交集为空），统一由 `nodeMastery` 函数管理掌握度。

## 五状态认知循环

### 状态定义

```tla
States == {"Idle", "Retrieving", "Solving", "Consolidating", "Expanding"}
```

### 状态迁移图

```
                         ┌─────────────┐
                         │    Idle     │
                         │  (空闲等待)  │
                         └──────┬──────┘
                                │ StartRetrieving
                                │ (取题，开始检索)
                         ┌──────▼──────┐
                         │ Retrieving  │
                         │  (检索关联)  │
                         └──┬───────┬──┘
             relatedK 非空  │       │  relatedK 为空
             且全部 mastery  │       │  或存在 mastery
             达到阈值 (≥80)  │       │  未达标 (<80)
                   ┌────────▼──┐  ┌─▼──────────┐
                   │  Solving  │  │ Expanding  │
                   │  (解题)   │  │ (扩展认知) │
                   └──┬────┬──┘  └──────┬─────┘
           答对       │    │ 答错       │
        ┌────────────▼┐   └─────────────┘
        │Consolidating│        │
        │  (巩固)     │        │
        └──────┬──────┘        │
               │ mastery+10    │
               ▼               ▼
             Idle             Idle
```

### 各状态详解

#### 1. Idle（空闲）

```tla
learnerState = "Idle"
```

系统的初始状态和每个周期完成后的回归点。在此状态下，`currentQuestion` 持有下一道待处理的题目。唯一的使能动作是 `StartRetrieving`。

#### 2. Retrieving（检索）

```tla
StartRetrieving ==
    /\ learnerState = "Idle"
    /\ learnerState' = "Retrieving"
    /\ UNCHANGED <<treeK2P, nodeMastery, currentQuestion>>
```

核心操作由 `GetRelatedNodes(q)` 完成：

```tla
GetRelatedNodes(q) ==
    LET targetP == QuestionPatternMap[q]
    IN <<targetP,
        {k \in Knowledge : treeK2P[k][targetP] = TRUE},
        PatternInherentErrors[targetP]>>
```

返回值是一个三元组 `<<Pattern, 已关联的Knowledge集合, 固有的ErrorPoint集合>>`。

检索结果决定下一步：

- **RetrieveSuccess**：关联的 Knowledge 和 ErrorPoint **全部**达到 mastery ≥ 80 → 进入 Solving
- **RetrieveFail**：存在未关联或未达标的节点 → 进入 Expanding

```tla
RetrieveSuccess ==
    /\ learnerState = "Retrieving"
    /\ LET related == GetRelatedNodes(currentQuestion) IN
           /\ related[2] # {}                           -- 有已关联的知识点
           /\ \A k \in related[2] : nodeMastery[k] >= 80  -- 全部达标
           /\ \A e \in related[3] : nodeMastery[e] >= 80  -- 全部达标
    /\ learnerState' = "Solving"

RetrieveFail ==
    /\ learnerState = "Retrieving"
    /\ LET related == GetRelatedNodes(currentQuestion) IN
           \/ related[2] = {}                            -- 无关联知识点
           \/ \E k \in related[2] : nodeMastery[k] < 80  -- 有关联但未达标
           \/ \E e \in related[3] : nodeMastery[e] < 80  -- 易错点未达标
    /\ learnerState' = "Expanding"
```

#### 3. Solving（解题）

```tla
SolveCorrectly ==
    /\ learnerState = "Solving"
    /\ learnerState' = "Consolidating"

SolveIncorrectly ==
    /\ learnerState = "Solving"
    /\ learnerState' = "Expanding"
```

模型中的 Solving 是一个**非确定性分支**：既可以答对也可以答错。TLC 会探索两条路径。这种设计反映了真实学习中"即使知识点都掌握了，仍可能犯错"的情况。

答对 → Consolidating（巩固，小幅提升 mastery）  
答错 → Expanding（扩展认知，针对性强化弱点）

#### 4. Consolidating（巩固）

```tla
Consolidate ==
    /\ learnerState = "Consolidating"
    /\ LET nodesToBoost == related[2] \cup related[3] \cup {related[1]}
       IN nodeMastery' = [n \in AllNodes |->
           IF n \in nodesToBoost
           THEN (IF nodeMastery[n] + 10 < 100 THEN nodeMastery[n] + 10 ELSE 100)
           ELSE nodeMastery[n]]
    /\ learnerState' = "Idle"
    /\ currentQuestion' \in QuestionSet
```

答对后对**所有相关节点**（当前 Pattern + 关联 Knowledge + 固有 ErrorPoint）提升 10 点 mastery（上限 100）。之后选择下一题，回到 Idle。

#### 5. Expanding（扩展）

最复杂的状态，有**两个互斥分支**：

**分支一：强化弱节点**（`relatedK # {}`）

```tla
weakK == {k \in relatedK : nodeMastery[k] < 80}
weakE == {e \in relatedE : nodeMastery[e] < 80}
```

对 mastery 未达标的 Knowledge 和 ErrorPoint 各提升 30 点。如果全部已达标，则不改变 mastery。

**分支二：新建连接**（`relatedK = {}`）

```tla
\E k1 \in Knowledge : \E k2 \in Knowledge :
    /\ k1 # k2
    /\ treeK2P' = [k \in Knowledge |->
        IF k = k1 \/ k = k2
        THEN [treeK2P[k] EXCEPT ![targetP] = TRUE]
        ELSE treeK2P[k]]
```

当当前 Pattern 还没有任何 Knowledge 连接时，选择两个不同的 Knowledge 节点建立连接。这是模型"从零开始学习"的机制。

## 辅助函数

### GetRelatedNodes(q)

```tla
GetRelatedNodes(q) ==
    LET targetP == QuestionPatternMap[q]
    IN <<targetP,
        {k \in Knowledge : treeK2P[k][targetP] = TRUE},
        PatternInherentErrors[targetP]>>
```

返回 `<<目标Pattern, 已关联Knowledge集, 固有ErrorPoint集>>`。使用 `<1>`, `<2>`, `<3>` 访问三个分量。

### ChangeTo(q)

```tla
ChangeTo(q) == currentQuestion' = q
```

显式定义换题动作，用于在 Spec 中声明公平性约束：每道题都有机会被选到。

## 掌握度模型

```tla
nodeMastery \in [AllNodes -> 0..100]
MasteryThreshold == 80
```

- **初始值：** 所有节点 mastery = 0
- **提升方式：** Consolidate 阶段 +10；ExpandTree 强化阶段 +30
- **上限：** 100（通过 `IF x < 100 THEN x ELSE 100` 钳位）
- **单调性：** mastery 只增不减，保证学习过程收敛
- **达标阈值：** 80，用于判断是否可以进入 Solving 以及 StrongEnough 是否成立

## StrongEnough 性质

```tla
StrongEnough ==
    \A p \in ExamPatterns :
        LET relatedK == {k \in Knowledge : treeK2P[k][p] = TRUE}
            inherentE == PatternInherentErrors[p]
        IN  /\ relatedK # {}
            /\ \A k \in relatedK : nodeMastery[k] >= MasteryThreshold
            /\ \A e \in inherentE : nodeMastery[e] >= MasteryThreshold
```

对每个考题对应的 Pattern：
1. 至少有一个关联的 Knowledge 节点（不能是空连接）
2. 所有关联的 Knowledge 节点 mastery ≥ 80
3. 所有固有的 ErrorPoint 节点 mastery ≥ 80

当且仅当这三条全部满足时，学生对该 Pattern 才算"真正掌握"。
