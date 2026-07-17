-- ============================================================
-- 03. 构建清洗分析表
-- 输入：ecommerce_all
-- 输出：ecommerce_clean
-- ============================================================

CREATE TABLE ecommerce_clean AS
SELECT
    STR_TO_DATE(
        REPLACE(TRIM(event_time), ' UTC', ''),
        '%Y-%m-%d %H:%i:%s'
    ) AS event_time,
    TRIM(event_type) AS event_type,
    product_id,
    category_id,
    NULLIF(TRIM(category_code), '') AS category_code,
    NULLIF(TRIM(brand), '') AS brand,
    CAST(price AS DECIMAL(12, 2)) AS price,
    user_id,
    NULLIF(TRIM(user_session), '') AS user_session,
    CASE WHEN price > 0 THEN 1 ELSE 0 END AS is_valid_price
FROM (
    SELECT DISTINCT
        event_time, event_type, product_id, category_id,
        category_code, brand, price, user_id, user_session
    FROM ecommerce_all
) AS deduplicated;

-- 清洗结果验证
SELECT
    COUNT(*) AS clean_rows,
    MIN(event_time) AS min_event_time,
    MAX(event_time) AS max_event_time,
    SUM(event_time IS NULL) AS invalid_time_rows,
    SUM(is_valid_price = 0) AS invalid_price_rows,
    SUM(category_code IS NULL) AS missing_category_code,
    SUM(brand IS NULL) AS missing_brand,
    SUM(user_session IS NULL) AS missing_user_session,
    COUNT(DISTINCT user_id) AS user_count,
    COUNT(DISTINCT product_id) AS product_count
FROM ecommerce_clean;

