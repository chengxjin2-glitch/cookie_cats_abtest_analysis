---
# Cookie Cats — Gate Position A/B Test Analysis
游戏关卡门位置 A/B 实验全流程分析

## 核心结论

| 指标 | gate_30（对照） | gate_40（实验） | Δ | p值 | 结论 |
|---|---|---|---|---|---|
| 7日留存率（主指标） | 19.02% | 18.20% | +0.82 pp | 0.0016 | 显著 ✅ |
| 1日留存率（次要） | 44.82% | 44.23% | +0.59 pp | 0.074 | 不显著 ❌ |
| 人均游戏局数（护栏） | 52.46局 | 51.30局 | +1.16局 | — | 方向一致 |

**最终建议：保留 gate_30，不上线 gate_40。**
门位置制造「预约式回访」节律，是留存正向驱动而非单纯摩擦；错误上线 gate_40 估算月度留存损失约 8,200 人。

---

## 分析流程

| 阶段 | 内容 |
|---|---|
| Phase 0 实验设计 | 假设预注册 · 双侧检验规则（α=0.05）· 指标体系 · 用户级随机化设计 |
| Phase 1 功效分析 | MDE=1pp · 需24,657人/组 · 实际样本44,700/45,489 · 实际功效96.6% |
| Phase 2 数据入库 | VARCHAR Staging策略 · CASE WHEN显式转换 · NULL无损审计（结果=0） |
| Phase 3 有效性检查 | SRM卡方检验（χ²=6.90，p=0.0086，边界性记录）· 跨组污染检查（0人）· 异常值处理 |
| Phase 4 统计检验 | 双比例z检验 · 95%置信区间 · 重尾分布检验限制说明 · 多重检验处理 |
| Phase 5 业务影响 | 规模化损失估算 · 预约式回访机制解释 · 统计显著性vs实际显著性讨论 |
| Phase 6 决策 | 基于预注册规则的最终建议 · 后续实验假设 · 分析局限性 |

---

## 文件说明

| 文件 | 说明 |
|---|---|
| `01_data_import.sql` | 建表、VARCHAR Staging入库、CASE WHEN类型转换、NULL无损校验 |
| `02_base_metric.sql` | SRM检查、跨组污染检查、核心指标聚合（留存率/游戏局数）、数据质量探查 |
| `abtest.py` | 完整Python分析：数据重建→有效性检查→功效分析→z检验→Bootstrap说明→可视化 |
| `compare.csv` | SQL聚合输出的分组指标摘要，作为Python脚本的输入文件 |
| `ab_test_results.png` | 6图可视化：分组大小SRM · 1日/7日留存对比 · 游戏局数 · 7日留存95%CI · 决策摘要 |
| `CookieCats_ABTest_Report.pdf` | 完整分析报告（7页），含实验设计文档、数据处理、统计检验、业务决策 |

---

## 工具链

- **数据库**：MySQL · DBeaver
- **Python**：pandas · numpy · scipy · matplotlib
- **可视化**：Power BI · matplotlib

---

## 数据来源

Cookie Cats 公开实验数据集，由 Tactile Entertainment 提供，通过 DataCamp 发布。
共 90,189 名玩家 · 5个字段（userid / version / sum_gamerounds / retention_1 / retention_7）· 实验窗口内全部新安装用户。

> 说明：本项目为对已完成公开实验数据的回溯分析；实验设计文档按企业上线前规范复原。
