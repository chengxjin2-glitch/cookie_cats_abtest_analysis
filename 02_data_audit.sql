-- ============================================================
-- 04. 全周期核心指标
-- 说明：数据缺少 order_id 和 quantity，购买记录称为购买事件，
--       金额称为交易金额估算，不将其表述为严格订单数、GMV或客单价。
-- ============================================================

-- 4.1 清洗后的行为分布
SELECT
    event_type,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS user_count,
    COUNT(DISTINCT user_session) AS session_count
FROM ecommerce_clean
GROUP BY event_type
ORDER BY event_count DESC;

-- 4.2 全周期指标
WITH base_metrics AS (
    SELECT
        COUNT(*) AS total_events,
        COUNT(DISTINCT user_id) AS active_users,
        COUNT(DISTINCT product_id) AS active_products,
        COUNT(DISTINCT user_session) AS total_sessions,
        COUNT(DISTINCT CASE
            WHEN event_type = 'purchase' THEN user_id
        END) AS purchase_users,
        COUNT(DISTINCT CASE
            WHEN event_type = 'purchase' THEN user_session
        END) AS purchase_sessions,
        SUM(CASE
            WHEN event_type = 'purchase' THEN 1 ELSE 0
        END) AS purchase_events,
        SUM(CASE
            WHEN event_type = 'purchase' AND is_valid_price = 1 THEN 1 ELSE 0
        END) AS valid_purchase_events,
        ROUND(SUM(CASE
            WHEN event_type = 'purchase' AND is_valid_price = 1 THEN price ELSE 0
        END), 2) AS estimated_transaction_amount
    FROM ecommerce_clean
)
SELECT
    total_events,
    active_users,
    active_products,
    total_sessions,
    purchase_users,
    purchase_sessions,
    purchase_events,
    valid_purchase_events,
    estimated_transaction_amount,
    ROUND(100.0 * purchase_users / NULLIF(active_users, 0), 2)
        AS user_purchase_conversion_pct,
    ROUND(100.0 * purchase_sessions / NULLIF(total_sessions, 0), 2)
        AS session_purchase_conversion_pct,
    ROUND(estimated_transaction_amount / NULLIF(valid_purchase_events, 0), 2)
        AS avg_purchase_event_amount
FROM base_metrics;

