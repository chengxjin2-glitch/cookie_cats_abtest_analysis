-- ============================================================
-- 01. 合并五个月度行为表
-- 运行环境：MySQL 8.0+
-- 输入表：2019_oct, 2019_nov, 2019_dec, 2020_jan, 2020_feb
-- 输出表：ecommerce_all
-- 注意：请在空白分析库中执行；本脚本不会覆盖已存在的同名表。
-- ============================================================

CREATE TABLE ecommerce_all AS
SELECT event_time, event_type, product_id, category_id,
       category_code, brand, price, user_id, user_session
FROM 2019_oct

UNION ALL

SELECT event_time, event_type, product_id, category_id,
       category_code, brand, price, user_id, user_session
FROM 2019_nov

UNION ALL

SELECT event_time, event_type, product_id, category_id,
       category_code, brand, price, user_id, user_session
FROM 2019_dec

UNION ALL

SELECT event_time, event_type, product_id, category_id,
       category_code, brand, price, user_id, user_session
FROM 2020_jan

UNION ALL

SELECT event_time, event_type, product_id, category_id,
       category_code, brand, price, user_id, user_session
FROM 2020_feb;

-- 合并前后行数校验：merged_rows 应等于 source_rows_sum。
SELECT
    (SELECT COUNT(*) FROM 2019_oct) AS rows_2019_oct,
    (SELECT COUNT(*) FROM 2019_nov) AS rows_2019_nov,
    (SELECT COUNT(*) FROM 2019_dec) AS rows_2019_dec,
    (SELECT COUNT(*) FROM 2020_jan) AS rows_2020_jan,
    (SELECT COUNT(*) FROM 2020_feb) AS rows_2020_feb,
    (SELECT COUNT(*) FROM 2019_oct)
      + (SELECT COUNT(*) FROM 2019_nov)
      + (SELECT COUNT(*) FROM 2019_dec)
      + (SELECT COUNT(*) FROM 2020_jan)
      + (SELECT COUNT(*) FROM 2020_feb) AS source_rows_sum,
    (SELECT COUNT(*) FROM ecommerce_all) AS merged_rows;

