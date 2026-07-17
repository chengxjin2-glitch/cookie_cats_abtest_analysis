-- ============================================================
-- 06. 趋势、高低点、日环比与7日移动平均
-- ============================================================

-- 6.1 行为数 Top 5
SELECT event_date, daily_events
FROM ecommerce_daily_metrics
ORDER BY daily_events DESC
LIMIT 5;

-- 6.2 行为数 Bottom 5
SELECT event_date, daily_events
FROM ecommerce_daily_metrics
ORDER BY daily_events ASC
LIMIT 5;

-- 6.3 购买事件数 Top/Bottom 5
SELECT event_date, daily_purchase_events
FROM ecommerce_daily_metrics
ORDER BY daily_purchase_events DESC
LIMIT 5;

SELECT event_date, daily_purchase_events
FROM ecommerce_daily_metrics
ORDER BY daily_purchase_events ASC
LIMIT 5;

-- 6.4 交易金额估算 Top/Bottom 5
SELECT event_date, daily_estimated_transaction_amount
FROM ecommerce_daily_metrics
ORDER BY daily_estimated_transaction_amount DESC
LIMIT 5;

SELECT event_date, daily_estimated_transaction_amount
FROM ecommerce_daily_metrics
ORDER BY daily_estimated_transaction_amount ASC
LIMIT 5;

-- 6.5 用户购买转化率 Top/Bottom 5
SELECT event_date, daily_user_purchase_conversion_pct
FROM ecommerce_daily_metrics
ORDER BY daily_user_purchase_conversion_pct DESC
LIMIT 5;

SELECT event_date, daily_user_purchase_conversion_pct
FROM ecommerce_daily_metrics
ORDER BY daily_user_purchase_conversion_pct ASC
LIMIT 5;

-- 6.6 会话购买转化率 Top/Bottom 5
SELECT event_date, daily_session_purchase_conversion_pct
FROM ecommerce_daily_metrics
ORDER BY daily_session_purchase_conversion_pct DESC
LIMIT 5;

SELECT event_date, daily_session_purchase_conversion_pct
FROM ecommerce_daily_metrics
ORDER BY daily_session_purchase_conversion_pct ASC
LIMIT 5;

-- 6.7 行为数和交易金额日环比
WITH previous_data AS (
    SELECT
        event_date,
        daily_events,
        LAG(daily_events, 1) OVER (ORDER BY event_date)
            AS previous_daily_events,
        daily_estimated_transaction_amount,
        LAG(daily_estimated_transaction_amount, 1) OVER (ORDER BY event_date)
            AS previous_daily_amount
    FROM ecommerce_daily_metrics
)
SELECT
    event_date,
    daily_events,
    previous_daily_events,
    ROUND(
        (daily_events - previous_daily_events) * 100.0
        / NULLIF(previous_daily_events, 0),
        2
    ) AS event_growth_pct,
    daily_estimated_transaction_amount,
    previous_daily_amount,
    ROUND(
        (daily_estimated_transaction_amount - previous_daily_amount) * 100.0
        / NULLIF(previous_daily_amount, 0),
        2
    ) AS amount_growth_pct
FROM previous_data
WHERE previous_daily_events IS NOT NULL
  AND previous_daily_amount IS NOT NULL
ORDER BY event_date;

-- 6.8 7日移动平均
-- 因每日表一天一行且日期连续，当前行加前6行等价于最多7个连续自然日。
SELECT
    event_date,
    daily_events,
    ROUND(AVG(daily_events) OVER (
        ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS avg_7d_events,
    daily_purchase_events,
    ROUND(AVG(daily_purchase_events) OVER (
        ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS avg_7d_purchase_events,
    daily_estimated_transaction_amount,
    ROUND(AVG(daily_estimated_transaction_amount) OVER (
        ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS avg_7d_transaction_amount,
    daily_user_purchase_conversion_pct,
    ROUND(AVG(daily_user_purchase_conversion_pct) OVER (
        ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS avg_7d_daily_user_conversion_pct
FROM ecommerce_daily_metrics
ORDER BY event_date;
