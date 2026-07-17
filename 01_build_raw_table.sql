/* =========================================================
   Project: E-commerce User Behavior and Operating Analysis
   Module: RFM Customer Value Segmentation
   Database: MySQL 8.0+
   Source table: ecommerce_clean

   RFM definitions:
   - R: days from the user's latest purchase to the day after
        the dataset observation end.
   - F: distinct purchase sessions, used as a proxy for orders.
   - M: sum of purchase prices where is_valid_price = 1 (price > 0).

   Important limitations:
   - The dataset has no reliable order_id.
   - F is purchase-session frequency, not audited order count.
   - M is estimated transaction amount, not audited GMV.
   ========================================================= */


/* =========================================================
   1. RFM input audit
   ========================================================= */

WITH observation_period AS (
    SELECT
        MIN(DATE(event_time)) AS observation_start_date,
        MAX(DATE(event_time)) AS observation_end_date

    FROM ecommerce_clean
),

purchase_audit AS (
    SELECT
        MIN(DATE(event_time)) AS purchase_start_date,
        MAX(DATE(event_time)) AS purchase_end_date,
        COUNT(DISTINCT user_id) AS purchase_users,
        COUNT(*) AS purchase_events,

        SUM(
            CASE WHEN is_valid_price = 1 THEN 1 ELSE 0 END
        ) AS valid_purchase_events,

        COUNT(DISTINCT user_id, user_session) AS purchase_sessions,

        SUM(
            CASE WHEN user_session IS NULL THEN 1 ELSE 0 END
        ) AS null_session_purchase_events,

        ROUND(
            SUM(
                CASE WHEN is_valid_price = 1 THEN price ELSE 0 END
            ),
            2
        ) AS estimated_transaction_amount

    FROM ecommerce_clean

    WHERE event_type = 'purchase'
)

SELECT
    o.observation_start_date,
    o.observation_end_date,
    p.purchase_start_date,
    p.purchase_end_date,
    p.purchase_users,
    p.purchase_events,
    p.valid_purchase_events,
    p.purchase_sessions,
    p.null_session_purchase_events,
    p.estimated_transaction_amount

FROM observation_period AS o

CROSS JOIN purchase_audit AS p;


/* =========================================================
   2. Build user-level RFM base table
   Grain: one row per purchasing user
   ========================================================= */

DROP TABLE IF EXISTS ecommerce_user_rfm_base;

CREATE TABLE ecommerce_user_rfm_base AS

WITH date_reference AS (
    SELECT
        DATE_ADD(
            MAX(DATE(event_time)),
            INTERVAL 1 DAY
        ) AS reference_date

    FROM ecommerce_clean
),

user_purchase_base AS (
    SELECT
        user_id,
        MAX(DATE(event_time)) AS last_purchase_date,
        COUNT(DISTINCT user_session) AS purchase_sessions,
        COUNT(*) AS purchase_events,

        SUM(
            CASE WHEN is_valid_price = 1 THEN 1 ELSE 0 END
        ) AS valid_purchase_events,

        ROUND(
            SUM(
                CASE WHEN is_valid_price = 1 THEN price ELSE 0 END
            ),
            2
        ) AS monetary_value

    FROM ecommerce_clean

    WHERE event_type = 'purchase'
      AND user_id IS NOT NULL

    GROUP BY user_id
)

SELECT
    u.user_id,
    u.last_purchase_date,

    DATEDIFF(
        d.reference_date,
        u.last_purchase_date
    ) AS recency_days,

    u.purchase_sessions,
    u.purchase_events,
    u.valid_purchase_events,
    u.monetary_value

FROM user_purchase_base AS u

CROSS JOIN date_reference AS d;

ALTER TABLE ecommerce_user_rfm_base
ADD PRIMARY KEY (user_id);


/* =========================================================
   3. Validate RFM base table

   Verified expected values:
   - rfm_users: 110,518
   - min_recency_days: 1
   - max_recency_days: 152
   - total_purchase_sessions: 155,617
   - total_purchase_events: 1,286,102
   - total_valid_purchase_events: 1,285,982
   - total_monetary_value: 6,348,267.70
   ========================================================= */

SELECT
    COUNT(*) AS rfm_users,
    MIN(recency_days) AS min_recency_days,
    MAX(recency_days) AS max_recency_days,
    MIN(purchase_sessions) AS min_purchase_sessions,
    SUM(purchase_sessions) AS total_purchase_sessions,
    SUM(purchase_events) AS total_purchase_events,
    SUM(valid_purchase_events) AS total_valid_purchase_events,

    ROUND(
        SUM(monetary_value),
        2
    ) AS total_monetary_value

FROM ecommerce_user_rfm_base;


/* =========================================================
   4. Inspect RFM distributions before scoring
   ========================================================= */

SELECT
    MIN(recency_days) AS min_recency,
    ROUND(AVG(recency_days), 2) AS avg_recency,
    MAX(recency_days) AS max_recency,
    MIN(purchase_sessions) AS min_frequency,
    ROUND(AVG(purchase_sessions), 2) AS avg_frequency,
    MAX(purchase_sessions) AS max_frequency,

    SUM(
        CASE WHEN purchase_sessions = 1 THEN 1 ELSE 0 END
    ) AS one_session_users,

    ROUND(
        100.0 * SUM(
            CASE WHEN purchase_sessions = 1 THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS one_session_user_pct,

    MIN(monetary_value) AS min_monetary,
    ROUND(AVG(monetary_value), 2) AS avg_monetary,
    MAX(monetary_value) AS max_monetary,

    SUM(
        CASE WHEN monetary_value = 0 THEN 1 ELSE 0 END
    ) AS zero_monetary_users

FROM ecommerce_user_rfm_base;


/* =========================================================
   5. Build RFM score table

   Scoring strategy:
   - R: PERCENT_RANK, descending recency. Lower recency gets
        a higher score; equal values receive equal scores.
   - F: fixed thresholds because 78.91% of users have one
        purchase session, making NTILE unsuitable.
   - M: PERCENT_RANK, ascending monetary value. Higher value
        gets a higher score; equal values receive equal scores.
   ========================================================= */

DROP TABLE IF EXISTS ecommerce_user_rfm_scores;

CREATE TABLE ecommerce_user_rfm_scores AS

WITH rfm_percentiles AS (
    SELECT
        user_id,
        last_purchase_date,
        recency_days,
        purchase_sessions,
        purchase_events,
        valid_purchase_events,
        monetary_value,

        PERCENT_RANK() OVER (
            ORDER BY recency_days DESC
        ) AS r_percentile,

        PERCENT_RANK() OVER (
            ORDER BY monetary_value ASC
        ) AS m_percentile

    FROM ecommerce_user_rfm_base
),

rfm_scored AS (
    SELECT
        user_id,
        last_purchase_date,
        recency_days,
        purchase_sessions,
        purchase_events,
        valid_purchase_events,
        monetary_value,
        r_percentile,
        m_percentile,

        CASE
            WHEN r_percentile <= 0.20 THEN 1
            WHEN r_percentile <= 0.40 THEN 2
            WHEN r_percentile <= 0.60 THEN 3
            WHEN r_percentile <= 0.80 THEN 4
            ELSE 5
        END AS r_score,

        CASE
            WHEN purchase_sessions = 1 THEN 1
            WHEN purchase_sessions = 2 THEN 2
            WHEN purchase_sessions = 3 THEN 3
            WHEN purchase_sessions BETWEEN 4 AND 5 THEN 4
            ELSE 5
        END AS f_score,

        CASE
            WHEN m_percentile <= 0.20 THEN 1
            WHEN m_percentile <= 0.40 THEN 2
            WHEN m_percentile <= 0.60 THEN 3
            WHEN m_percentile <= 0.80 THEN 4
            ELSE 5
        END AS m_score

    FROM rfm_percentiles
)

SELECT
    user_id,
    last_purchase_date,
    recency_days,
    purchase_sessions,
    monetary_value,
    purchase_events,
    valid_purchase_events,
    r_percentile,
    m_percentile,
    r_score,
    f_score,
    m_score,

    CONCAT(
        r_score,
        f_score,
        m_score
    ) AS rfm_code,

    r_score + f_score + m_score AS rfm_total_score

FROM rfm_scored;

ALTER TABLE ecommerce_user_rfm_scores
ADD PRIMARY KEY (user_id);


/* =========================================================
   6. Validate RFM score table
   ========================================================= */

SELECT
    COUNT(*) AS rfm_users,
    MIN(r_score) AS min_r_score,
    MAX(r_score) AS max_r_score,
    MIN(f_score) AS min_f_score,
    MAX(f_score) AS max_f_score,
    MIN(m_score) AS min_m_score,
    MAX(m_score) AS max_m_score,
    MIN(rfm_total_score) AS min_total_score,
    MAX(rfm_total_score) AS max_total_score,

    SUM(
        CASE
            WHEN r_score IS NULL
              OR f_score IS NULL
              OR m_score IS NULL
            THEN 1
            ELSE 0
        END
    ) AS null_score_users

FROM ecommerce_user_rfm_scores;

ALTER TABLE ecommerce_user_rfm_segments
ADD PRIMARY KEY (user_id);


/* =========================================================
   7. Build RFM customer segment table

   High R: r_score >= 4 (recent purchasers)
   High F: f_score >= 2 (at least two purchase sessions)
   High M: m_score >= 4 (upper monetary groups)
   ========================================================= */

DROP TABLE IF EXISTS ecommerce_user_rfm_segments;

CREATE TABLE ecommerce_user_rfm_segments AS

SELECT
    user_id,
    last_purchase_date,
    recency_days,
    purchase_sessions,
    monetary_value,
    purchase_events,
    valid_purchase_events,
    r_score,
    f_score,
    m_score,
    rfm_code,
    rfm_total_score,

    CASE
        WHEN r_score >= 4 AND f_score >= 2 AND m_score >= 4
            THEN '重要价值用户'
        WHEN r_score < 4 AND f_score >= 2 AND m_score >= 4
            THEN '重要保持用户'
        WHEN r_score >= 4 AND f_score = 1 AND m_score >= 4
            THEN '重要发展用户'
        WHEN r_score < 4 AND f_score = 1 AND m_score >= 4
            THEN '重要挽留用户'
        WHEN r_score >= 4 AND f_score >= 2 AND m_score < 4
            THEN '一般价值用户'
        WHEN r_score < 4 AND f_score >= 2 AND m_score < 4
            THEN '一般保持用户'
        WHEN r_score >= 4 AND f_score = 1 AND m_score < 4
            THEN '一般发展用户'
        ELSE '一般挽留用户'
    END AS customer_segment

FROM ecommerce_user_rfm_scores;


/* =========================================================
   8. Build BI-ready RFM segment summary table
   ========================================================= */

DROP TABLE IF EXISTS ecommerce_rfm_segment_summary;

CREATE TABLE ecommerce_rfm_segment_summary AS

WITH segment_base AS (
    SELECT
        customer_segment,
        COUNT(*) AS user_count,
        ROUND(AVG(recency_days), 2) AS avg_recency_days,
        ROUND(AVG(purchase_sessions), 2) AS avg_purchase_sessions,
        ROUND(AVG(monetary_value), 2) AS avg_monetary_value,
        ROUND(SUM(monetary_value), 2) AS total_monetary_value

    FROM ecommerce_user_rfm_segments

    GROUP BY customer_segment
)

SELECT
    customer_segment,
    user_count,

    ROUND(
        100.0 * user_count / NULLIF(SUM(user_count) OVER (), 0),
        2
    ) AS user_share_pct,

    avg_recency_days,
    avg_purchase_sessions,
    avg_monetary_value,
    total_monetary_value,

    ROUND(
        100.0 * total_monetary_value
        / NULLIF(SUM(total_monetary_value) OVER (), 0),
        2
    ) AS monetary_share_pct

FROM segment_base;

ALTER TABLE ecommerce_rfm_segment_summary
ADD PRIMARY KEY (customer_segment);


/* =========================================================
   9. View RFM segment summary
   Verified totals:
   - 8 segments
   - 110,518 users
   - 6,348,267.70 estimated transaction amount
   ========================================================= */

SELECT
    customer_segment,
    user_count,
    user_share_pct,
    avg_recency_days,
    avg_purchase_sessions,
    avg_monetary_value,
    total_monetary_value,
    monetary_share_pct

FROM ecommerce_rfm_segment_summary

ORDER BY total_monetary_value DESC;
