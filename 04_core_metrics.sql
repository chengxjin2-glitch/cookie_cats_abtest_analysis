/* =========================================================
   Project: E-commerce User Behavior and Operating Analysis
   Module: Category Performance and Conversion Drill-down
   Database: MySQL 8.0+
   Source table: ecommerce_clean

   Contents:
   1. Dimension completeness audit
   2. Purchase-price quality audit
   3. Category-level metric table
   4. Result-table validation
   5. Estimated transaction amount TOP 10
   6. Valid purchase event TOP 10
   7. High-traffic, low-conversion categories

   Important definitions:
   - purchase_events includes all purchase events.
   - valid_purchase_events requires is_valid_price = 1 (price > 0).
   - estimated_transaction_amount is an estimate, not audited GMV.
   - Category conversion uses a user-level loose funnel. It does not
     require the events to occur in one session or in chronological order.
   ========================================================= */


/* =========================================================
   1. Dimension completeness audit
   ========================================================= */

WITH dimension_quality_audit AS (
    SELECT
        COUNT(*) AS total_events,

        SUM(
            CASE
                WHEN brand IS NULL OR TRIM(brand) = '' THEN 1
                ELSE 0
            END
        ) AS missing_brand_events,

        COUNT(
            DISTINCT NULLIF(TRIM(brand), '')
        ) AS distinct_brands,

        SUM(
            CASE
                WHEN category_id IS NULL THEN 1
                ELSE 0
            END
        ) AS missing_category_id_events,

        COUNT(DISTINCT category_id) AS distinct_category_ids,

        SUM(
            CASE
                WHEN category_code IS NULL OR TRIM(category_code) = '' THEN 1
                ELSE 0
            END
        ) AS missing_category_code_events,

        COUNT(
            DISTINCT NULLIF(TRIM(category_code), '')
        ) AS distinct_category_codes

    FROM ecommerce_clean
)

SELECT
    total_events,
    missing_brand_events,
    ROUND(
        100.0 * missing_brand_events / NULLIF(total_events, 0),
        2
    ) AS missing_brand_pct,
    distinct_brands,
    missing_category_id_events,
    ROUND(
        100.0 * missing_category_id_events / NULLIF(total_events, 0),
        2
    ) AS missing_category_id_pct,
    distinct_category_ids,
    missing_category_code_events,
    ROUND(
        100.0 * missing_category_code_events / NULLIF(total_events, 0),
        2
    ) AS missing_category_code_pct,
    distinct_category_codes

FROM dimension_quality_audit;


/* =========================================================
   2. Purchase-price quality audit
   ========================================================= */

SELECT
    COUNT(*) AS purchase_events,

    SUM(
        CASE
            WHEN price IS NULL THEN 1
            ELSE 0
        END
    ) AS null_price_purchase_events,

    SUM(
        CASE
            WHEN price <= 0 THEN 1
            ELSE 0
        END
    ) AS non_positive_price_purchase_events,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN price <= 0 THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        4
    ) AS non_positive_price_pct,

    MIN(price) AS min_purchase_price,
    MAX(price) AS max_purchase_price

FROM ecommerce_clean

WHERE event_type = 'purchase';


/* =========================================================
   3. Build category-level metric table
   Grain: one row per category_id
   ========================================================= */

DROP TABLE IF EXISTS ecommerce_category_metrics;

CREATE TABLE ecommerce_category_metrics AS

WITH category_base AS (
    SELECT
        category_id,
        COUNT(*) AS total_events,

        SUM(
            CASE WHEN event_type = 'view' THEN 1 ELSE 0 END
        ) AS view_events,

        SUM(
            CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END
        ) AS cart_events,

        SUM(
            CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END
        ) AS purchase_events,

        SUM(
            CASE
                WHEN event_type = 'purchase' AND is_valid_price = 1 THEN 1
                ELSE 0
            END
        ) AS valid_purchase_events,

        COUNT(DISTINCT product_id) AS active_products,

        ROUND(
            SUM(
                CASE
                    WHEN event_type = 'purchase' AND is_valid_price = 1 THEN price
                    ELSE 0
                END
            ),
            2
        ) AS estimated_transaction_amount

    FROM ecommerce_clean

    GROUP BY category_id
),

user_category_flags AS (
    SELECT
        category_id,
        user_id,

        MAX(
            CASE WHEN event_type = 'view' THEN 1 ELSE 0 END
        ) AS has_view,

        MAX(
            CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END
        ) AS has_cart,

        MAX(
            CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END
        ) AS has_purchase

    FROM ecommerce_clean

    WHERE user_id IS NOT NULL

    GROUP BY
        category_id,
        user_id
),

category_funnel AS (
    SELECT
        category_id,

        SUM(
            CASE WHEN has_view = 1 THEN 1 ELSE 0 END
        ) AS view_users,

        SUM(
            CASE
                WHEN has_view = 1 AND has_cart = 1 THEN 1
                ELSE 0
            END
        ) AS cart_stage_users,

        SUM(
            CASE
                WHEN has_view = 1
                 AND has_cart = 1
                 AND has_purchase = 1
                THEN 1
                ELSE 0
            END
        ) AS purchase_stage_users

    FROM user_category_flags

    GROUP BY category_id
)

SELECT
    b.category_id,
    b.total_events,
    b.view_events,
    b.cart_events,
    b.purchase_events,
    b.valid_purchase_events,
    b.active_products,
    f.view_users,
    f.cart_stage_users,
    f.purchase_stage_users,
    b.estimated_transaction_amount,

    ROUND(
        100.0 * f.cart_stage_users / NULLIF(f.view_users, 0),
        2
    ) AS loose_view_to_cart_pct,

    ROUND(
        100.0 * f.purchase_stage_users / NULLIF(f.cart_stage_users, 0),
        2
    ) AS loose_cart_to_purchase_pct,

    ROUND(
        100.0 * f.purchase_stage_users / NULLIF(f.view_users, 0),
        2
    ) AS loose_view_to_purchase_pct

FROM category_base AS b

LEFT JOIN category_funnel AS f
    ON b.category_id = f.category_id;

ALTER TABLE ecommerce_category_metrics
ADD PRIMARY KEY (category_id);


/* =========================================================
   4. Validate category result table
   Verified expected values:
   - category_count: 525
   - total_events: 19,583,742
   - purchase_events: 1,286,102
   - valid_purchase_events: 1,285,982
   - invalid_price_purchase_events: 120
   - total_estimated_transaction_amount: 6,348,267.70
   ========================================================= */

SELECT
    COUNT(*) AS category_count,
    SUM(total_events) AS total_events,
    SUM(purchase_events) AS purchase_events,
    SUM(valid_purchase_events) AS valid_purchase_events,
    SUM(purchase_events) - SUM(valid_purchase_events)
        AS invalid_price_purchase_events,
    ROUND(
        SUM(estimated_transaction_amount),
        2
    ) AS total_estimated_transaction_amount,
    MIN(estimated_transaction_amount) AS min_category_amount,
    MAX(estimated_transaction_amount) AS max_category_amount

FROM ecommerce_category_metrics;


/* =========================================================
   5. Estimated transaction amount TOP 10 categories
   ========================================================= */

WITH category_amount_rank AS (
    SELECT
        category_id,
        valid_purchase_events,
        purchase_stage_users,
        estimated_transaction_amount,

        SUM(estimated_transaction_amount) OVER ()
            AS total_estimated_transaction_amount,

        DENSE_RANK() OVER (
            ORDER BY estimated_transaction_amount DESC
        ) AS amount_rank

    FROM ecommerce_category_metrics
)

SELECT
    category_id,
    valid_purchase_events,
    purchase_stage_users,
    estimated_transaction_amount,

    ROUND(
        estimated_transaction_amount / NULLIF(valid_purchase_events, 0),
        2
    ) AS avg_valid_purchase_amount,

    ROUND(
        100.0 * estimated_transaction_amount
        / NULLIF(total_estimated_transaction_amount, 0),
        2
    ) AS amount_share_pct,

    amount_rank

FROM category_amount_rank

WHERE amount_rank <= 10

ORDER BY
    amount_rank,
    category_id;


/* =========================================================
   6. Valid purchase event TOP 10 categories
   ========================================================= */

WITH category_purchase_rank AS (
    SELECT
        category_id,
        valid_purchase_events,
        purchase_stage_users,
        estimated_transaction_amount,

        SUM(valid_purchase_events) OVER ()
            AS total_valid_purchase_events,

        DENSE_RANK() OVER (
            ORDER BY valid_purchase_events DESC
        ) AS purchase_event_rank,

        DENSE_RANK() OVER (
            ORDER BY estimated_transaction_amount DESC
        ) AS amount_rank

    FROM ecommerce_category_metrics
)

SELECT
    category_id,
    valid_purchase_events,
    purchase_stage_users,

    ROUND(
        100.0 * valid_purchase_events
        / NULLIF(total_valid_purchase_events, 0),
        2
    ) AS purchase_event_share_pct,

    estimated_transaction_amount,

    ROUND(
        estimated_transaction_amount / NULLIF(valid_purchase_events, 0),
        2
    ) AS avg_valid_purchase_amount,

    purchase_event_rank,
    amount_rank

FROM category_purchase_rank

WHERE purchase_event_rank <= 10

ORDER BY
    purchase_event_rank,
    category_id;


/* =========================================================
   7. High-traffic, low-conversion categories

   High traffic:
   - view_users in the highest quartile.

   Low conversion:
   - category loose view-to-purchase rate is below the
     weighted category benchmark.
   ========================================================= */

WITH category_evaluation AS (
    SELECT
        category_id,
        view_users,
        cart_stage_users,
        purchase_stage_users,
        estimated_transaction_amount,
        loose_view_to_cart_pct,
        loose_view_to_purchase_pct,

        ROUND(
            100.0 * SUM(purchase_stage_users) OVER ()
            / NULLIF(SUM(view_users) OVER (), 0),
            2
        ) AS overall_view_to_purchase_pct,

        NTILE(4) OVER (
            ORDER BY view_users DESC
        ) AS traffic_quartile,

        DENSE_RANK() OVER (
            ORDER BY view_users DESC
        ) AS traffic_rank,

        DENSE_RANK() OVER (
            ORDER BY estimated_transaction_amount DESC
        ) AS amount_rank

    FROM ecommerce_category_metrics
)

SELECT
    category_id,
    view_users,
    cart_stage_users,
    purchase_stage_users,
    estimated_transaction_amount,
    loose_view_to_cart_pct,
    loose_view_to_purchase_pct,
    overall_view_to_purchase_pct,

    ROUND(
        loose_view_to_purchase_pct - overall_view_to_purchase_pct,
        2
    ) AS conversion_gap_pct,

    traffic_quartile,
    traffic_rank,
    amount_rank

FROM category_evaluation

WHERE traffic_quartile = 1
  AND loose_view_to_purchase_pct < overall_view_to_purchase_pct

ORDER BY view_users DESC

LIMIT 10;
