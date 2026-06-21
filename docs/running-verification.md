# 运行验证

## 前置条件

### JDK

TLC 运行在 JVM 上，需要 JDK 21 或更高版本：

```bash
java -version
# java version "21.0.5" 2024-10-15 LTS
```

如果未安装，从 [Oracle JDK](https://www.oracle.com/java/technologies/downloads/) 或 [OpenJDK](https://openjdk.org/) 获取。

### tla2tools.jar

TLA+ 官方工具集，包含 SANY 解析器和 TLC 模型检验器。从 GitHub Release 下载：

```bash
curl -sL "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar" \
  -o tla2tools.jar
```

约 4MB。放置于项目根目录即可（`.gitignore` 已排除）。

## 运行验证

### 方式一：自包含模型（推荐）

```bash
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC \
  -config MC.cfg MC_bkxh_model.tla
```

- `-XX:+UseParallelGC`：启用并行 GC，TLC 推荐选项（可省略，省略时 TLC 会警告）
- `-cp tla2tools.jar`：classpath 指向 TLA+ 工具 jar
- `tlc2.TLC`：TLC 入口类
- `-config MC.cfg`：配置文件
- `MC_bkxh_model.tla`：待验证的 TLA+ 模块

### 方式二：INSTANCE 包装器

```bash
java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC \
  -config MC_original.cfg MC_original.tla
```

此命令验证的是原始参数化规范（`MindTreeCognitiveArch_V9_1`），通过 `MC_original.tla` 代入常量后运行。

### 可选参数

| 参数 | 作用 |
|------|------|
| `-nowarning` | 抑制 ParallelGC 警告 |
| `-workers N` | 并行工作线程数（默认 auto，等于 CPU 核心数） |
| `-fp N` | 指纹集大小（默认自动调整） |
| `-deadlock` | 额外检查死锁（本模型无死锁，无需使用） |
| `-coverage N` | 覆盖度分析（1=按位置） |

### 预期输出

```
TLC2 Version 2026.05.26.235334 (rev: 4ba7d88)
Running breadth-first search Model-Checking with fp 110 and seed ...
Parsing file ...\MC_bkxh_model.tla
...
Semantic processing of module MC_bkxh_model
Starting...
Implied-temporal checking--satisfiability problem has 1 branches.
Computing initial states...
Finished computing initial states: 1 distinct state generated at ...
Progress(56) at ...: 90 states generated, 67 distinct states found,
  0 states left on queue.
Checking temporal properties for the complete state space with 67 total
  distinct states at ...
Finished checking temporal properties in 00s at ...
Model checking completed. No error has been found.
  Estimates of the probability that TLC did not check all reachable states
  because two distinct states had the same fingerprint:
  calculated (optimistic):  val = 8.4E-17
90 states generated, 67 distinct states found, 0 states left on queue.
The depth of the complete state graph search is 56.
The average outdegree of the complete state graph is 1
  (minimum is 0, the maximum 2 and the 95th percentile is 2).
Finished in 00s at (...)
```

### 关键指标解读

| 指标 | 值 | 含义 |
|------|-----|------|
| distinct states | 67 | 全状态空间大小——所有可达状态 |
| states generated | 90 | 探索过程中生成的状态总数（含重复） |
| states left on queue | 0 | **穷举搜索完成**，不存在未探索的后继状态 |
| depth | 56 | 状态图最长路径深度 |
| fingerprint collision | 8.4E-17 | 哈希碰撞导致漏检的概率——极低 |
| outdegree max | 2 | 任何状态最多有 2 个后继（如 Solving→Consolidating 或 Solving→Expanding 的非确定性分支） |

## 常见问题

### 1. "Precedence conflict between ops \lor ... and \land"

**原因：** TLA+ 解析器无法消歧嵌套的 `\/` 和 `/\` 优先级。

**解决：** 用显式括号包裹每个分支：
```tla
-- 错误
\/ A \/ B /\ C

-- 正确
\/ (/\ A /\ B)
\/ (/\ C)
```

### 2. "Unknown operator: `MIN'"

**原因：** `MIN` 不是标准 TLA+ 运算符。

**解决：** 替换为 IF-THEN-ELSE：
```tla
-- 错误
MIN(nodeMastery[n] + 30, 100)

-- 正确
(IF nodeMastery[n] + 30 < 100 THEN nodeMastery[n] + 30 ELSE 100)
```

### 3. "Unknown operator: `k1'"

**原因：** 在 bulleted `/\` 列表中，量词 `\E k1 \in S : ...` 的作用域仅限于该 bullet 项。下一行引用 `k1` 时它已超出作用域。

```tla
-- 错误：k1 在下一行脱靶
/\ \E k1 \in Knowledge : \E k2 \in Knowledge : k1 # k2
/\ treeK2P' = [... IF k = k1 ...]   -- k1 不可见！

-- 正确：将依赖 k1/k2 的表达式合并到同一作用域
/\ \E k1 \in Knowledge : \E k2 \in Knowledge :
     /\ k1 # k2
     /\ treeK2P' = [... IF k = k1 ...]
```

### 4. "TLC found an error in the configuration file"

**原因：** TLC 的 `.cfg` 解析器只支持有限表达式语法，不支持函数构造器 `[x \in S |-> e]` 或 `[k |-> v]`。

**解决：** 将函数类型常量定义移到 `.tla` 包装文件中，通过 `INSTANCE ... WITH` 传入。

### 5. "Substitution missing for symbol ..."

**原因：** 使用 `INSTANCE M WITH ...` 时，M 中声明的所有 CONSTANTS 和 VARIABLES 都必须提供替换。

**解决：** 确保 `WITH` 子句覆盖原始模块中每个 `CONSTANTS` 和 `VARIABLES` 声明。

### 6. 内存不足

小模型（< 1000 states）通常只需几十 MB。如果需要验证更大的实例：

```bash
java -XX:+UseParallelGC -Xmx8G -cp tla2tools.jar tlc2.TLC ...
```

增加堆内存上限。

## 修改常量值

编辑 `MC_bkxh_model.tla` 中对应的定义即可。例如扩大实例：

```tla
-- 从 2 Knowledge → 4 Knowledge
Knowledge == {K1, K2, K3, K4}

-- 从 1 Pattern → 2 Pattern
Pattern == {P1, P2}

-- 多个 Pattern 时需更新 QuestionPatternMap
QuestionPatternMap == [q \in {Q1} |-> P1]  -- 或 [Q1 |-> P1, Q2 |-> P2]
```

修改后重新运行 TLC。注意状态空间可能指数增长。

## CI/CD 集成

可将 TLC 验证作为 CI 检查步骤：

```yaml
# GitHub Actions 示例
- name: TLC Model Check
  run: |
    curl -sL "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar" -o tla2tools.jar
    java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -config MC.cfg MC_bkxh_model.tla
```

TLC 以非零退出码报告失败，可直接作为 CI 判断依据。
