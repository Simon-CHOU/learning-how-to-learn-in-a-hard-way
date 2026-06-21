# MindTree Cognitive Architecture — TLA+ 形式化验证

基于思维树（MindTree）方法论的认知架构状态机模型，通过 TLC 模型检验器验证了安全性与活性。

**验证状态：** `TypeInvariant` ✅ &nbsp; `EventuallyPassExam` ✅

---

## TL;DR

这是一个 TLA+ 规范，描述了一个从 **知识节点**（Knowledge）和 **错误模式**（ErrorPoint）出发，通过 **模式节点**（Pattern）组织，在五个状态间迁移的认知过程。TLC 在 67 个可达状态的全状态空间上通过了类型不变式和最终掌握性质的双重验证。

```bash
# 获取 tla2tools.jar 后（见下文），一行验证：
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -config MC.cfg MC_bkxh_model.tla
# 预期输出：Model checking completed. No error has been found.
```

---

## 模型概览

### 五状态认知循环

```
                    ┌──────────┐
                    │   Idle   │
                    └────┬─────┘
                         │ StartRetrieving
                    ┌────▼─────┐
                    │Retrieving│
                    └─┬────┬──┘
          relatedK≠{} │    │ relatedK={}
         ∧ mastery≥80 │    │ ∨ mastery<80
               ┌──────▼──┐ ┌▼──────────┐
               │ Solving  │ │ Expanding │
               └──┬───┬──┘ └─────┬─────┘
       correct /    \ incorrect   │ 建立/强化连接
              /      \            │ 提升 mastery
    ┌────────▼─┐  ┌──▼────────┐   │
    │Consolidat│  │ Expanding │◄──┘
    │ing       │  └──────────┘
    └────┬─────┘
         │ mastery+10
         ▼
       Idle
```

1. **Idle** — 空闲，等待取出下一题
2. **Retrieving** — 检索：查当前题目对应的 Pattern，找到关联的 Knowledge 和 ErrorPoint
3. **Solving** — 解题：检索到的节点全部达标（mastery ≥ 80），可以尝试解答
4. **Consolidating** — 巩固：答对后对相关节点 mastery+10（上限 100）
5. **Expanding** — 扩展：两种子策略
   - **强化弱节点**：关联存在但 mastery 不足 → 对薄弱节点 mastery+30
   - **新建连接**：Knowledge 到 Pattern 的关联不存在 → 选择两个 Knowledge 节点建立映射

### 三类节点

| 节点类型 | 含义 | 例子 |
|---------|------|------|
| `Knowledge` | 知识点 | 语法规则、公式、定义 |
| `Pattern` | 问题模式 | 题型模板、解题套路 |
| `ErrorPoint` | 易错点 | 常见错误、陷阱 |

每个 Pattern 关联一组 Knowledge 节点（通过 `treeK2P` 矩阵）和一组固有的 ErrorPoint（通过 `PatternInherentErrors`）。

`StrongEnough` 性质定义为：所有考题涉及的知识节点和易错节点 mastery 均 ≥ 80。

---

## 文件布局

```
.
├── bkxh-model.tlaplus.txt              # 原始 TLA+ 规范（参数化版本，含 CONSTANTS）
│
├── MC_bkxh_model.tla                   # ★ 推荐入口：自包含验证模型（常量已内联）
├── MC.cfg                              #   配套 TLC 配置文件
│
├── MindTreeCognitiveArch_V9_1.tla       # 原始规范的 .tla 副本（模块名匹配）
├── MC_original.tla                     # INSTANCE 包装器，引用原始规范验证
├── MC_original.cfg                     #   配套 TLC 配置文件
│
├── README.md
└── .gitignore                          # 排除 tla2tools.jar 及 TLC 产物
```

### 两个验证入口的区别

| 入口 | 适用场景 |
|------|---------|
| `MC_bkxh_model.tla` + `MC.cfg` | **日常使用**——一个文件包含所有常量定义，不依赖 CONSTANTS 替换 |
| `MC_original.tla` + `MC_original.cfg` | **回归验证**——通过 `INSTANCE ... WITH` 将原始参数化规范代入具体常量，确保原始文件修改后仍通过验证 |

---

## 运行验证

### 前置条件

- JDK 21+（`java -version` 确认）
- `tla2tools.jar`（TLA+ 工具集，约 4MB）

### 获取 tla2tools.jar

从官方 GitHub Release 下载：

```bash
curl -sL "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar" -o tla2tools.jar
```

### 运行

**方式一：自包含模型（推荐）**

```bash
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -config MC.cfg MC_bkxh_model.tla
```

**方式二：INSTANCE 包装器**

```bash
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -config MC_original.cfg MC_original.tla
```

### 预期输出

```
Model checking completed. No error has been found.
  Estimates of the probability that TLC did not check all reachable states
  because two distinct states had the same fingerprint:
  calculated (optimistic):  val = 8.4E-17
90 states generated, 67 distinct states found, 0 states left on queue.
The depth of the complete state graph search is 56.
```

关键指标：
- **67 distinct states** — 全状态空间，无遗漏
- **0 states left on queue** — 穷举搜索完成，无死锁
- **8.4E-17 碰撞概率** — 哈希碰撞导致漏检的概率极低

---

## 验证结果

### TypeInvariant（类型不变式）— ✅ 通过

```tla
TypeInvariant ==
    /\ learnerState \in States
    /\ treeK2P \in [Knowledge -> [Pattern -> BOOLEAN]]
    /\ nodeMastery \in [AllNodes -> 0..100]
    /\ currentQuestion \in QuestionSet
```

确保所有变量始终在合法范围内：状态不越界、mastery 不超 [0,100]、树映射保持正确的函数类型。

### EventuallyPassExam（活性性质）— ✅ 通过（补齐公平性后）

```tla
EventuallyPassExam == <>[] StrongEnough
```

"最终，所有考试题目的关联节点都将持续达到掌握阈值。"

**初次验证时该性质失败**，根因是内部状态迁移动作缺乏公平性约束。TLA+ 允许任意状态无限 stuttering（口吃步），若 `ExpandTree` 等动作没有 `WF`（弱公平性）约束，系统可以在 `Expanding` 状态永远停留。

修复：为全部 6 个内部动作添加弱公平性：

```tla
Spec == Init /\ [][Next]_Vars
          /\ WF_<<learnerState>>(StartRetrieving)
          /\ WF_<<learnerState>>(RetrieveSuccess)    -- 补齐
          /\ WF_<<learnerState>>(RetrieveFail)       -- 补齐
          /\ WF_<<learnerState>>(SolveCorrectly)     -- 补齐
          /\ WF_<<learnerState>>(SolveIncorrectly)   -- 补齐
          /\ WF_<<learnerState>>(Consolidate)        -- 补齐
          /\ WF_<<learnerState>>(ExpandTree)         -- 补齐
          /\ \A q \in QuestionSet : WF_<<currentQuestion>>(ChangeTo(q))
```

### 小模型实例

当前验证使用最小满足 ASSUME 约束的实例：

| 常量 | 取值 | 说明 |
|------|------|------|
| `Knowledge` | `{k1, k2}` | 2 个知识点（ASSUME 要求 ≥2） |
| `Pattern` | `{p1}` | 1 个模式 |
| `ErrorPoint` | `{e1}` | 1 个易错点 |
| `QuestionSet` | `{q1}` | 1 道题目 |
| `MasteryThreshold` | `80` | 掌握阈值 |

实例虽小，但覆盖了全部状态迁移路径：RetrieveFail→ExpandTree（初始无连接）、ExpandTree 建连接、ExpandTree 强化弱节点、RetrieveSuccess→SolveCorrectly→Consolidate、SolveIncorrectly→ExpandTree。

---

## 模型设计要点

### Mastery 单调性

`nodeMastery` 只增不减（单调递增至 100 上限）。这保证了系统的"学习过程"具有收敛性——一旦某个节点达到 MasteryThreshold(80)，就不会再掉下来。

### ExpandTree 的双分支策略

```
relatedK # {} ──→ 弱节点强化 (+30) 或 不变（已达标）
relatedK = {} ──→ 建立新的 K→P 连接
```

第一分支对应"复习"，第二分支对应"学习新关联"。两者互斥，由 `treeK2P` 的当前状态决定走哪条。

### SANY 兼容性

原始规范中使用的 `MIN(a, b)` 和 `\E x, y \in S` 简写语法不被 SANY 解析器支持，已替换为标准 TLA+ 写法：

```tla
-- 前：MIN(nodeMastery[n] + 30, 100)
-- 后：(IF nodeMastery[n] + 30 < 100 THEN nodeMastery[n] + 30 ELSE 100)

-- 前：\E k1, k2 \in Knowledge : k1 # k2 /\ ...
-- 后：\E k1 \in Knowledge : \E k2 \in Knowledge : /\ k1 # k2 /\ ...
```

---

## 约束与扩展方向

### 当前约束

- **小实例**：仅 2 Knowledge + 1 Pattern + 1 ErrorPoint。更大的常量集需要调整 cfg 或 MC 文件。
- **单题**：`QuestionSet = {q1}`，多题目的交错行为未覆盖。
- **确定性阈值**：`MasteryThreshold = 80` 是写死的，可改为 CONSTANT 后在不同值上验证。

### 扩展方向

1. **扩大实例**：增加到 5+ Knowledge、3+ Pattern，观察状态空间膨胀
2. **交错调度**：多题目交替出现时的公平性行为
3. **遗忘机制**：引入 mastery 衰减（不再单调），验证活性是否仍保持
4. **概率扩展**：用 ProbTLC 分析不同学习策略的收敛概率

---

## 参考资料

- [TLA+ 官方文档](https://lamport.azurewebsites.net/tla/tla.html)
- [TLA+ GitHub](https://github.com/tlaplus/tlaplus)
- [TLC Model Checker](https://tla.msr-inria.inria.fr/tlatoolbox/doc/model/model-checker.html)
- 思维树方法论 —— @敝槛玄鹤
