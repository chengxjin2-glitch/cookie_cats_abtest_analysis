-- ============================================================
-- 05. 每日汇总指标表
-- 输出：ecommerce_daily_metrics（152行，一天一行）
-- ============================================================

CREATE TABLE ecommerce_daily_metrics AS
WITH daily_base AS (
    SELECT
        DATE(event_time) AS event_date,
        COUNT(*) AS daily_events,
        COUNT(DISTINCT user_id) AS daily_active_users,
        COUNT(DISTINCT product_id) AS daily_active_products,
        COUNT(DISTINCT user_session) AS daily_sessions,
        COUNT(DISTINCT CASE
            WHEN event_type = 'purchase' THEN user_id
        END) AS daily_purchase_users,
        COUNT(DISTINCT CASE
            WHEN event_type = 'purchase' THEN user_session
        END) AS daily_purchase_sessions,
        SUM(CASE
            WHEN event_type = 'purchase' THEN 1 ELSE 0
        END) AS daily_purchase_events,
        SUM(CASE
            WHEN event_type = 'purchase' AND is_valid_price = 1 THEN 1 ELSE 0
        END) AS daily_valid_purchase_events,
        ROUND(SUM(CASE
            WHEN event_type = 'purchase' AND is_valid_price = 1 THEN price ELSE 0
        END), 2) AS daily_estimated_transaction_amount
    FROM ecommerce_clean
    GROUP BY DATE(event_time)
)
SELECT
    event_date,
    daily_events,
    daily_active_users,
    daily_active_products,
    daily_sessions,
    daily_purchase_users,
    daily_purchase_sessions,
    daily_purchase_events,
    daily_valid_purchase_events,
    daily_estimated_transaction_amount,
    ROUND(100.0 * daily_purchase_users / NULLIF(daily_active_users, 0), 2)
        AS daily_user_purchase_conversion_pct,
    ROUND(100.0 * daily_purchase_sessions / NULLIF(daily_sessions, 0), 2)
        AS daily_session_purchase_conversion_pct,
    ROUND(daily_estimated_transaction_amount / NULLIF(daily_valid_purchase_events, 0), 2)
        AS daily_avg_purchase_event_amount
FROM daily_base;

ALTER TABLE ecommerce_daily_metrics
ADD PRIMARY KEY (event_date);

-- 每日表回算验证
SELECT
    COUNT(*) AS day_count,
    MIN(event_date) AS min_date,
    MAX(event_date) AS max_date,
    SUM(daily_events) AS total_events,
    SUM(daily_purchase_events) AS total_purchase_events,
    SUM(daily_valid_purchase_events) AS total_valid_purchase_events,
    ROUND(SUM(daily_estimated_transaction_amount), 2)
        AS total_estimated_transaction_amount
FROM ecommerce_daily_metrics;

