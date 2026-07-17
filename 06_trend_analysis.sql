-- ============================================================
-- 07. 用户级与会话级转化漏斗
-- 输入：ecommerce_clean
-- 输出：ecommerce_funnel_summary（3行，可直接供BI使用）
--
-- 漏斗类型：
-- 1. user_loose：同一用户在观察期内出现过相应行为，不限制会话和顺序。
-- 2. session_loose：同一用户、同一会话内出现过相应行为，不限制顺序。
-- 3. session_strict：同一用户、同一会话内满足
--    first_view_time < first_cart_time < first_purchase_time。
-- ============================================================

DROP TABLE IF EXISTS ecommerce_funnel_summary;

CREATE TABLE ecommerce_funnel_summary AS

WITH user_flags AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM ecommerce_clean
    WHERE user_id IS NOT NULL
    GROUP BY user_id
),

user_loose_counts AS (
    SELECT
        SUM(CASE WHEN has_view = 1 THEN 1 ELSE 0 END) AS view_stage_count,
        SUM(CASE
            WHEN has_view = 1 AND has_cart = 1 THEN 1 ELSE 0
        END) AS cart_stage_count,
        SUM(CASE
            WHEN has_view = 1 AND has_cart = 1 AND has_purchase = 1
            THEN 1 ELSE 0
        END) AS purchase_stage_count
    FROM user_flags
),

session_flags AS (
    SELECT
        user_id,
        user_session,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM ecommerce_clean
    WHERE user_id IS NOT NULL
      AND user_session IS NOT NULL
    GROUP BY
        user_id,
        user_session
),

session_loose_counts AS (
    SELECT
        SUM(CASE WHEN has_view = 1 THEN 1 ELSE 0 END) AS view_stage_count,
        SUM(CASE
            WHEN has_view = 1 AND has_cart = 1 THEN 1 ELSE 0
        END) AS cart_stage_count,
        SUM(CASE
            WHEN has_view = 1 AND has_cart = 1 AND has_purchase = 1
            THEN 1 ELSE 0
        END) AS purchase_stage_count
    FROM session_flags
),

session_first_event_time AS (
    SELECT
        user_id,
        user_session,
        MIN(CASE
            WHEN event_type = 'view' THEN event_time
        END) AS first_view_time,
        MIN(CASE
            WHEN event_type = 'cart' THEN event_time
        END) AS first_cart_time,
        MIN(CASE
            WHEN event_type = 'purchase' THEN event_time
        END) AS first_purchase_time
    FROM ecommerce_clean
    WHERE user_id IS NOT NULL
      AND user_session IS NOT NULL
      AND event_type IN ('view', 'cart', 'purchase')
    GROUP BY
        user_id,
        user_session
),

session_strict_counts AS (
    SELECT
        SUM(CASE
            WHEN first_view_time IS NOT NULL THEN 1 ELSE 0
        END) AS view_stage_count,
        SUM(CASE
            WHEN first_view_time IS NOT NULL
             AND first_cart_time IS NOT NULL
             AND first_view_time < first_cart_time
            THEN 1 ELSE 0
        END) AS cart_stage_count,
        SUM(CASE
            WHEN first_view_time IS NOT NULL
             AND first_cart_time IS NOT NULL
             AND first_purchase_time IS NOT NULL
             AND first_view_time < first_cart_time
             AND first_cart_time < first_purchase_time
            THEN 1 ELSE 0
        END) AS purchase_stage_count
    FROM session_first_event_time
),

funnel_counts AS (
    SELECT
        'user_loose' AS funnel_type,
        'user' AS analysis_unit,
        view_stage_count,
        cart_stage_count,
        purchase_stage_count
    FROM user_loose_counts

    UNION ALL

    SELECT
        'session_loose' AS funnel_type,
        'session' AS analysis_unit,
        view_stage_count,
        cart_stage_count,
        purchase_stage_count
    FROM session_loose_counts

    UNION ALL

    SELECT
        'session_strict' AS funnel_type,
        'session' AS analysis_unit,
        view_stage_count,
        cart_stage_count,
        purchase_stage_count
    FROM session_strict_counts
)

SELECT
    funnel_type,
    analysis_unit,
    view_stage_count,
    cart_stage_count,
    purchase_stage_count,
    ROUND(
        100.0 * cart_stage_count / NULLIF(view_stage_count, 0),
        2
    ) AS view_to_cart_pct,
    ROUND(
        100.0 * purchase_stage_count / NULLIF(cart_stage_count, 0),
        2
    ) AS cart_to_purchase_pct,
    ROUND(
        100.0 * purchase_stage_count / NULLIF(view_stage_count, 0),
        2
    ) AS view_to_purchase_pct
FROM funnel_counts;

ALTER TABLE ecommerce_funnel_summary
ADD PRIMARY KEY (funnel_type);


-- 07.1 漏斗结果验证
-- 已验证结果：
-- user_loose：1,597,754 → 358,026 → 104,757
-- session_loose：4,281,001 → 788,439 → 106,517
-- session_strict：4,281,001 → 587,041 → 71,310
SELECT
    funnel_type,
    analysis_unit,
    view_stage_count,
    cart_stage_count,
    purchase_stage_count,
    view_to_cart_pct,
    cart_to_purchase_pct,
    view_to_purchase_pct,
    CASE
        WHEN view_stage_count >= cart_stage_count
         AND cart_stage_count >= purchase_stage_count
        THEN 1 ELSE 0
    END AS is_stage_order_valid
FROM ecommerce_funnel_summary
ORDER BY FIELD(
    funnel_type,
    'user_loose',
    'session_loose',
    'session_strict'
);


-- 07.2 会话完整性检查
SELECT
    COUNT(*) AS total_events,
    SUM(CASE WHEN user_session IS NULL THEN 1 ELSE 0 END)
        AS null_session_events,
    ROUND(
        100.0 * SUM(CASE WHEN user_session IS NULL THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        4
    ) AS null_session_pct
FROM ecommerce_clean;


-- 07.3 宽松完整漏斗会话与去重用户核对
WITH session_flags AS (
    SELECT
        user_id,
        user_session,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS has_view,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM ecommerce_clean
    WHERE user_id IS NOT NULL
      AND user_session IS NOT NULL
    GROUP BY
        user_id,
        user_session
)
SELECT
    SUM(CASE
        WHEN has_view = 1 AND has_cart = 1 AND has_purchase = 1
        THEN 1 ELSE 0
    END) AS complete_funnel_sessions,
    COUNT(DISTINCT CASE
        WHEN has_view = 1 AND has_cart = 1 AND has_purchase = 1
        THEN user_id
    END) AS complete_funnel_users
FROM session_flags;
