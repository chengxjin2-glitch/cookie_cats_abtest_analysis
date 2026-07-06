/*
=============================================
/*
=============================================
脚本名称：cookie_cats_abtest_base_metric.sql
功能：Cookie Cats门限A/B实验基础指标计算 + 分流有效性校验
作者：数据分析师
适用场景：实验数据每日复盘、SRM前置校验、留存指标统计
表依赖：ABtest.cookie_cats
字段说明：
userid      用户唯一ID
version     实验分组 gate_30 / gate_40
sum_gamerounds  用户总游玩局数
retention_1_flag 1日留存标记 1=留存 0=流失
retention_7_flag 7日留存标记 1=留存 0=流失
=============================================
*/

-- ======================
-- 模块1：分流有效性校验1：输出跨分组异常用户明细
-- ======================
WITH user_group_distinct AS (
    SELECT 
        userid,
        GROUP_CONCAT(DISTINCT version SEPARATOR ',') AS belong_groups,
        COUNT(DISTINCT version) AS group_cnt
    FROM ABtest.cookie_cats
    GROUP BY userid
)
SELECT *
FROM user_group_distinct
WHERE group_cnt > 1;

-- ======================
-- 模块1补充：统计跨分组异常用户总数（结果=0代表分流无bug）
-- ======================
WITH user_group_distinct AS (
    SELECT 
        userid,
        COUNT(DISTINCT version) AS group_cnt
    FROM ABtest.cookie_cats
    GROUP BY userid
)
SELECT COUNT(DISTINCT userid) AS cross_group_error_user_count
FROM user_group_distinct
WHERE group_cnt > 1;

-- ======================
-- 模块2：核心业务指标聚合（分实验组输出标准指标）
-- ======================
SELECT
    version AS experiment_group,
    COUNT(DISTINCT userid) AS total_user_cnt, -- 分组总用户（去重）
    ROUND(AVG(retention_1_flag), 4) AS retention_1_rate, -- 1日留存率
    ROUND(AVG(retention_7_flag), 4) AS retention_7_rate, -- 7日留存率
    ROUND(AVG(sum_gamerounds), 2) AS avg_gamerounds, -- 人均平均游玩局数
    SUM(sum_gamerounds) AS total_gamerounds -- 分组总游玩局数
FROM ABtest.cookie_cats
GROUP BY version
ORDER BY version;

-- ======================
-- 模块3：辅助数据质量探查1：全局总用户校验
-- ======================
SELECT COUNT(DISTINCT userid) AS all_total_user FROM ABtest.cookie_cats;

-- ======================
-- 模块3：辅助数据质量探查2：留存标签分布校验
-- ======================
SELECT
    'retention_1' AS retention_type,
    retention_1_flag AS retain_label,
    COUNT(DISTINCT userid) AS user_count
FROM ABtest.cookie_cats
GROUP BY retention_1_flag
UNION ALL
SELECT
    'retention_7' AS retention_type,
    retention_7_flag AS retain_label,
    COUNT(DISTINCT userid) AS user_count
FROM ABtest.cookie_cats
GROUP BY retention_7_flag;

-- ======================
-- 模块3：辅助数据质量探查3：游玩局数极值探查（已删除不兼容的MEDIAN函数）
-- ======================
SELECT
    MIN(sum_gamerounds) AS min_rounds,
    MAX(sum_gamerounds) AS max_rounds,
    ROUND(AVG(sum_gamerounds), 2) AS mean_rounds
FROM ABtest.cookie_cats;