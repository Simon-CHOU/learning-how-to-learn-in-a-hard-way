# 模型设计要点

## Mastery 单调性

### 设计

`nodeMastery` 在整个系统生命周期中只增不减：

```tla
-- Consolidate：+10
nodeMastery' = [n \in AllNodes |->
    IF n \in nodesToBoost
    THEN (IF nodeMastery[n] + 10 < 100 THEN nodeMastery[n] + 10 ELSE 100)
    ELSE nodeMastery[n]]

-- ExpandTree 强化：+30
nodeMastery' = [n \in AllNodes |->
    IF n \in weakK \cup weakE
    THEN (IF nodeMastery[n] + 30 < 100 THEN nodeMastery[n] + 30 ELSE 100)
    ELSE nodeMastery[n]]
```

没有"遗忘"或"衰减"动作。mastery 一旦提升就不会下降。

### 理由

单调性保证了系统的**收敛性**：
1. 每次 ExpandTree 循环将弱节点 mastery 提升 30
2. 阈值是 80，最多需要 ceil(80/30) = 3 次 ExpandTree 即可达标
3. 因为只增不减，一旦 StrongEnough 成立就永远成立（`[]StrongEnough`）
4. 结合公平性，保证 `<>[]StrongEnough`（最终永远掌握）

### 局限

真实学习中存在遗忘。引入 mastery 衰减（如每个周期 -5）会使活性性质的验证更复杂——系统可能永远在"学会→遗忘→学会"的循环中振荡。这不是当前模型的设计目标，但可作为后续扩展方向。

## ExpandTree 的双分支策略

### 设计

ExpandTree 有两个互斥分支，由 `relatedK` 是否为空决定：

**分支一：relatedK ≠ {}**（知识节点已关联到当前 Pattern）

- 子分支 1.1：存在弱节点 → 强化它们（+30）
- 子分支 1.2：不存在弱节点 → 不改变 mastery（nop 分支）

**分支二：relatedK = {}**（当前 Pattern 无任何 Knowledge 连接）

- 选择两个不同的 Knowledge 节点，建立到当前 Pattern 的连接

### 理由

这两个分支对应学习过程中的两种根本不同的活动：

- **分支一对应"复习"**：知识点已经学过（有连接），但还没掌握到位（mastery 不足），需要强化训练
- **分支二对应"初学"**：面对全新题型，需要从已知知识点中寻找适用的，建立初步关联

分支一的子分支 1.2（nop）看起来是冗余的——既然 mastery 已全部达标，为什么不直接进入 Solving？答案在 RetrieveFail 的判定逻辑中。当 `relatedK ≠ {}` 但存在 mastery < 80 的节点时进入 Expanding；而当所有节点都已达标时，RetrieveSuccess 会触发，根本不会进入 Expanding。但在 Expanding 内部，如果 weakK 和 weakE 都为空（理论上在 relatedK ≠ {} 前提下不应发生，但 TLA+ 要求完备的分支覆盖），nop 分支确保 Next 关系始终有定义。

### 非确定性

```tla
\/ (/\ relatedK # {}
    /\ (\/ (...weak nodes...) \/ (...nop...))
    /\ UNCHANGED treeK2P)
\/ (/\ relatedK = {}
    /\ \E k1, k2 \in Knowledge : k1 # k2
    /\ ...)
```

分支一和分支二的互斥由 `relatedK # {}` 和 `relatedK = {}` 保证——任何状态下恰好一个成立。分支一内部的子分支也互斥（有弱节点 vs 无弱节点），保证每一步的状态迁移是确定的（对给定的树状态和 mastery 状态）。

唯一的非确定性在 Solving 状态（答对/答错）和 Expanding 分支二中 Knowledge 节点的选择（`\E k1, k2` 意味着任意两个不同的 Knowledge 节点都可以被选中——在当前 2-Knowledge 实例中是确定的，但在 3+ Knowledge 实例中 TLC 会探索所有组合）。

## SANY 兼容性修复

TLC 使用的 SANY 解析器是严格的 TLA+ 语法解析器。原始规范使用了两种不被 SANY 支持的简写或非标准语法：

### MIN 替换

```tla
-- 原始（不兼容）
MIN(nodeMastery[n] + 30, 100)

-- 修复（标准 TLA+）
(IF nodeMastery[n] + 30 < 100 THEN nodeMastery[n] + 30 ELSE 100)
```

`MIN`/`MAX` 不是 TLA+ 标准库的一部分（某些工具的自定义扩展中有，但 SANY 不认）。标准写法是内联 IF-THEN-ELSE。

### 量词简写替换

```tla
-- 原始（不兼容）
\E k1, k2 \in Knowledge : k1 # k2

-- 修复（标准 TLA+）
\E k1 \in Knowledge : \E k2 \in Knowledge : k1 # k2
```

`\E x, y \in S : P` 在 Lamport 的 TLA+ 书中被提到为合法简写，但 SANY 解析器的某些版本不支持多变量量词简写。拆成嵌套 `\E` 是保险写法。

### 量词作用域修复

```tla
-- 原始（不兼容：k1/k2 在下一行脱靶）
/\ \E k1 \in Knowledge : \E k2 \in Knowledge : k1 # k2
/\ treeK2P' = [... IF k = k1 \/ k = k2 ...]

-- 修复（将依赖 k1/k2 的表达式纳入量词作用域）
/\ \E k1 \in Knowledge : \E k2 \in Knowledge :
     /\ k1 # k2
     /\ treeK2P' = [... IF k = k1 \/ k = k2 ...]
```

在 TLA+ 的 bulleted `/\` 列表中，每个 `/\` 是一个独立子公式。第一个 `/\` 中的量词作用域仅限于该行。第二个 `/\` 中引用 `k1` 和 `k2` 会导致"Unknown operator"语义错误。

### 优先级消歧

```tla
-- 原始（歧义：\/ 和 /\ 的嵌套优先级冲突）
/\ ( \/ (weakK # {} \/ weakE # {})
       /\ nodeMastery' = ...
   \/ (weakK = {} /\ weakE = {})
       /\ UNCHANGED nodeMastery
  )

-- 修复（显式括号）
/\ ( \/ (/\ (weakK # {} \/ weakE # {})
        /\ nodeMastery' = ...)
   \/ (/\ weakK = {}
        /\ weakE = {}
        /\ UNCHANGED nodeMastery)
  )
```

SANY 严格按照 TLA+ 语法规则解析。`\/` 的一个分支包含 `/\` 列表时，必须用显式括号包裹，不能仅靠缩进推断。

## 公平性设计

### 为什么需要 8 个 WF 条件

TLA+ 的 stuttering 语义意味着任何状态都可以"什么都不做"。公平性约束告诉模型检验器："某些事情最终必须发生"。

```tla
Spec == Init /\ [][Next]_Vars
          /\ WF_<<learnerState>>(StartRetrieving)
          /\ WF_<<learnerState>>(RetrieveSuccess)
          /\ WF_<<learnerState>>(RetrieveFail)
          /\ WF_<<learnerState>>(SolveCorrectly)
          /\ WF_<<learnerState>>(SolveIncorrectly)
          /\ WF_<<learnerState>>(Consolidate)
          /\ WF_<<learnerState>>(ExpandTree)
          /\ \A q \in QuestionSet : WF_<<currentQuestion>>(ChangeTo(q))
```

每个状态至少有一个 WF 覆盖的动作：

| 状态 | 覆盖动作 |
|------|---------|
| Idle | StartRetrieving |
| Retrieving | RetrieveSuccess, RetrieveFail |
| Solving | SolveCorrectly, SolveIncorrectly |
| Consolidating | Consolidate |
| Expanding | ExpandTree |

如果某个状态缺少公平性约束，TLC 会找到一个反例：系统在该状态无限 stuttering，活性性质无法满足。

### 为什么用 WF 而非 SF

**弱公平性（WF）：** 如果动作持续 enabled，它最终必须发生。  
**强公平性（SF）：** 如果动作反复 enabled（即使中间 disabled），它最终必须发生。

本模型选择 WF，因为：
1. 每个状态的使能动作是确定的——从 Expanding 只能做 ExpandTree，动作不会 disabled 后又 enabled
2. WF 在 TLC 中验证效率更高
3. 模型不涉及"动作被其他动作打断后又恢复"的模式

### ChangeTo 的公平性

```tla
\A q \in QuestionSet : WF_<<currentQuestion>>(ChangeTo(q))
```

这确保每道题都有机会被选到。对于当前 `QuestionSet = {Q1}` 的实例是退化的（只有一道题），但在多题目实例中，它防止系统只选某一道题而永远忽略其他题目。

## 小模型实例的价值

选择最小的合法实例（2 Knowledge + 1 Pattern + 1 ErrorPoint + 1 Question）是刻意为之：

1. **完备覆盖**：67 个状态覆盖了所有 7 种动作和全部状态迁移路径
2. **快速迭代**：验证在毫秒级完成，适合开发中频繁运行
3. **反例可读**：如果性质失败，反例轨迹短（12 步），易于人工分析
4. **满足 ASSUME**：是最小的满足所有 ASSUME 约束的实例
   - `Cardinality(Knowledge) >= 2` ✓
   - `PatternInherentErrors[p] # {}` ✓
   - 三集合互不相交 ✓

更大的实例用于压力测试和发现规模相关问题，但日常验证用小实例即可获得高置信度。
