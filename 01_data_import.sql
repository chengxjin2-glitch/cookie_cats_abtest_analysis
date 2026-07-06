-- 1. 删除旧表（如果之前建过错表）
DROP TABLE IF EXISTS cookie_cats;

-- 2. 新建适配的表（字段类型100%匹配CSV）
CREATE TABLE cookie_cats (
    userid INT PRIMARY KEY,          -- 无重复用户ID，设为主键
    version VARCHAR(20),             -- 存储gate_30/gate_40
    sum_gamerounds INT,              -- 游戏局数（含异常值49854）
    retention_1 VARCHAR(10),         -- 存True/False，后续可转1/0
    retention_7 VARCHAR(10)          -- 同上
);
-- =============================================
-- ⚠️ 手动操作步骤：在此处通过DBeaver数据导入功能上传cookie_cats.csv
-- 导入完成后，再执行下方所有SQL语句
-- =============================================

-- 1. 校验原始字符串取值，确认无异常小写true/空值/空白字符
SELECT retention_1, retention_7, COUNT(*) 
FROM cookie_cats 
GROUP BY retention_1, retention_7;

-- 2. 新增标准数值标记列，显式完成数据转换

ALTER TABLE cookie_cats ADD COLUMN retention_1_flag TINYINT;
ALTER TABLE cookie_cats ADD COLUMN retention_7_flag TINYINT;

UPDATE cookie_cats SET
  retention_1_flag = CASE WHEN retention_1 = 'True' THEN 1 
                          WHEN retention_1 = 'False' THEN 0 END,
  retention_7_flag = CASE WHEN retention_7 = 'True' THEN 1 
                          WHEN retention_7 = 'False' THEN 0 END;

-- 3. 转换无损校验：结果必须为0，代表无数据丢失、无转换失败行
SELECT COUNT(*) FROM cookie_cats 
WHERE retention_1_flag IS NULL OR retention_7_flag IS NULL;