# 文件布局

## 目录结构

```
bkxh-model/
├── bkxh-model.tlaplus.txt              # 原始 TLA+ 规范（参数化版本）
│
├── MC_bkxh_model.tla                   # ★ 推荐入口：自包含验证模型
├── MC.cfg                              #   配套 TLC 配置
│
├── MindTreeCognitiveArch_V9_1.tla       # 原始规范的 .tla 副本
├── MC_original.tla                     # INSTANCE 包装器
├── MC_original.cfg                     #   配套 TLC 配置
│
├── docs/                               # 详细文档
│   ├── model-overview.md
│   ├── file-layout.md
│   ├── running-verification.md
│   ├── verification-results.md
│   ├── design-decisions.md
│   └── constraints-and-roadmap.md
│
├── README.md
└── .gitignore
```

## 文件详解

### bkxh-model.tlaplus.txt

**类型：** 原始 TLA+ 规范（源文件）

**模块名：** `MindTreeCognitiveArch_V9_1`

这是模型的形式化规范本身。使用 `CONSTANTS` 声明参数，用 `ASSUME` 约束参数的合法取值范围：

```tla
CONSTANTS
    QuestionSet, Knowledge, Pattern, ErrorPoint,
    QuestionPatternMap, MasteryThreshold, PatternInherentErrors

ASSUME
    /\ QuestionPatternMap \in [QuestionSet -> Pattern]
    /\ Cardinality(Knowledge) >= 2
    /\ PatternInherentErrors \in [Pattern -> SUBSET ErrorPoint]
    /\ \A p \in Pattern : PatternInherentErrors[p] # {}
    /\ MasteryThreshold = 80
    -- ... 以及集合互不相交等约束
```

参数化设计的目的是让同一个规范可以代入不同规模的实例进行验证——可以用 2 个 Knowledge 节点快速迭代，也可以用 100 个 Knowledge 节点做压力测试。

**为什么不直接在此文件上跑 TLC：** 因为 `QuestionPatternMap` 和 `PatternInherentErrors` 是函数类型常量，TLC 的 `.cfg` 配置解析器不支持函数表达式。因此需要通过 `.tla` 包装文件提供具体值。

### MC_bkxh_model.tla + MC.cfg（推荐入口）

**类型：** 自包含验证模型

这是**日常开发验证的首选入口**。它直接内联了所有常量定义，不依赖 CONSTANTS 替换：

```tla
-- 内联常量
Q1 == "q1"
K1 == "k1"
K2 == "k2"
P1 == "p1"
E1 == "e1"

QuestionSet        == {Q1}
Knowledge          == {K1, K2}
Pattern            == {P1}
ErrorPoint         == {E1}
QuestionPatternMap == [q \in QuestionSet |-> P1]
PatternInherentErrors == [p \in Pattern |-> {E1}]
MasteryThreshold   == 80
```

然后完整复制了原始规范中的所有状态定义、动作定义、不变式和性质。

**优点：**
- 一个文件包含所有内容，无需理解 CONSTANTS/INSTANCE 机制
- TLC 配置极简（仅 3 行）
- 修改常量值只需编辑一个文件

**缺点：**
- 与原始规范是代码复制关系，修改原始规范后需手动同步
- 不适合频繁修改原始规范的开发流程

**配套 cfg：**
```
SPECIFICATION Spec
INVARIANT TypeInvariant
PROPERTY EventuallyPassExam
```

### MindTreeCognitiveArch_V9_1.tla

**类型：** 原始规范的 `.tla` 副本

内容与 `bkxh-model.tlaplus.txt` 完全一致（含所有修复），但使用标准 `.tla` 扩展名，且文件名与模块名（`MindTreeCognitiveArch_V9_1`）匹配。

**存在原因：** TLA+ 工具链通过模块名查找文件。当 `MC_original.tla` 执行 `INSTANCE MindTreeCognitiveArch_V9_1` 时，SANY 解析器会在当前目录搜索 `MindTreeCognitiveArch_V9_1.tla`。此文件满足该查找约定。

### MC_original.tla + MC_original.cfg

**类型：** INSTANCE 包装验证

这是**回归验证入口**——确保原始规范（参数化版本）在代入具体常量后仍通过验证：

```tla
---- MODULE MC_original ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

VARIABLES learnerState, treeK2P, nodeMastery, currentQuestion

-- 提供常量定义
Q1 == "q1"
-- ... (同上)

-- 引入原始规范，替换 CONSTANTS 和 VARIABLES
INSTANCE MindTreeCognitiveArch_V9_1 WITH
    QuestionSet           <- QuestionSet,
    Knowledge             <- Knowledge,
    Pattern               <- Pattern,
    ErrorPoint            <- ErrorPoint,
    QuestionPatternMap    <- QuestionPatternMap,
    MasteryThreshold      <- 80,
    PatternInherentErrors <- PatternInherentErrors,
    learnerState          <- learnerState,
    treeK2P               <- treeK2P,
    nodeMastery           <- nodeMastery,
    currentQuestion       <- currentQuestion
====
```

`INSTANCE ... WITH` 是 TLA+ 的模块参数化机制。它将原始模块的所有定义导入当前模块，同时将 CONSTANTS 和 VARIABLES 替换为本地定义。

**关键语法要点：**
- 所有 CONSTANTS 和 VARIABLES 都必须提供替换（缺一不可，否则语义错误）
- 替换后的 `Spec` 等定义直接可用（无需模块前缀），因为未使用重命名 INSTANCE
- 原始模块中的 `ASSUME` 约束不会被导入（ASSUME 仅对原始模块自身生效），因此常量值必须自行保证满足约束

**使用场景：**
- 修改 `bkxh-model.tlaplus.txt` 后，运行此入口确认未引入回归
- 用不同常量组合（如更大的 QuestionSet）验证同一规范

## 两个入口的对比

| 维度 | MC_bkxh_model.tla | MC_original.tla |
|------|-------------------|-----------------|
| 依赖 | 无外部依赖 | 依赖 MindTreeCognitiveArch_V9_1.tla |
| 常量修改 | 直接编辑 .tla 文件 | 编辑 MC_original.tla 中的定义 |
| 规范同步 | 手动复制 | 自动（INSTANCE 引用） |
| 适用场景 | 日常开发、快速迭代 | 回归验证、多实例验证 |
| TLC 配置 | 3 行 | 3 行（相同） |
| 验证结果 | 67 states, 90 generated | 67 states, 90 generated（一致） |

## .gitignore

```
tla2tools.jar          # TLA+ 工具二进制（约 4MB）
states/                # TLC 状态队列目录
*.bin                  # TLC 指纹存储文件
*_TTrace_*.tla         # TLC 自动生成的反例轨迹
```

`tla2tools.jar` 需由用户自行下载（见 [运行验证](running-verification.md)），不纳入版本控制。TLC 运行时产生的临时文件同样被排除。
