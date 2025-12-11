/* =====================================================================
   CUSTOMER ANALYTICS
   ---------------------------------------------------------------------
   Part of: Retail Analytics & Returns Intelligence System
   This file contains all customer-level analytical modules including:
   - Lifetime value calculations
   - Repeat purchase behaviour
   - Retention & churn identification
   - Customer contribution by country
   - Monthly active customer trends
===================================================================== */

USE inventory;


/* ================================================================
   ANALYSIS 1: Customer Lifetime Value (LTV) Summary
   ----------------------------------------------------------------
   - Total revenue per customer
   - Total returns per customer
   - Net value = revenue – returns
   - First and last activity dates
================================================================ */

WITH customer_sales AS (
    SELECT
        CustomerID,
        SUM(Order_Value)              AS total_sales_value,
        COUNT(DISTINCT InvoiceNo)     AS n_orders,
        MIN(InvoiceDate)              AS first_order_date,
        MAX(InvoiceDate)              AS last_order_date
    FROM sales_classified
    WHERE 
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY CustomerID
),

customer_returns AS (
    SELECT
        CustomerID,
        SUM(-Order_Value) AS total_returns_value   -- convert to positive value
    FROM returns_classified
    WHERE 
        CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY CustomerID
)

SELECT
    cs.CustomerID,
    ROUND(cs.total_sales_value, 2)                      AS total_sales_value,
    ROUND(COALESCE(cr.total_returns_value, 0), 2)       AS total_returns_value,
    ROUND(
        cs.total_sales_value - COALESCE(cr.total_returns_value, 0),
        2
    )                                                   AS net_value,
    cs.n_orders,
    cs.first_order_date,
    cs.last_order_date
FROM customer_sales cs
LEFT JOIN customer_returns cr
    ON cs.CustomerID = cr.CustomerID
ORDER BY net_value DESC;



/* ================================================================
   ANALYSIS 2: Repeat Purchase Behaviour
   ----------------------------------------------------------------
   - Counts:
       * total_customers
       * repeat_customers (n_orders > 1)
       * repeat_customer_rate = repeat_customers / total_customers
================================================================ */

WITH customer_order_counts AS (
    SELECT
        CustomerID,
        COUNT(DISTINCT InvoiceNo) AS n_orders
    FROM sales_classified
    WHERE 
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY CustomerID
)

SELECT
    COUNT(*)                                               AS total_customers,
    SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END)         AS repeat_customers,
    ROUND(
        SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        4
    ) AS repeat_customer_rate
FROM customer_order_counts;



/* ================================================================
   ANALYSIS 3: Customer Retention & Churn Overview
   ----------------------------------------------------------------
   - Identifies:
       * Customers active in the first AND last month (retained)
       * Customers active in the first month but not the last (churned)
   - Returns a compact summary with counts and percentages
================================================================ */

WITH date_bounds AS (
    SELECT
        DATE_FORMAT(MIN(InvoiceDate), '%Y-%m') AS first_month,
        DATE_FORMAT(MAX(InvoiceDate), '%Y-%m') AS last_month
    FROM sales_classified
),

customers_first_month AS (
    SELECT DISTINCT CustomerID
    FROM sales_classified, date_bounds
    WHERE DATE_FORMAT(InvoiceDate, '%Y-%m') = first_month
      AND CustomerID IS NOT NULL
      AND CustomerID <> 0
),

customers_last_month AS (
    SELECT DISTINCT CustomerID
    FROM sales_classified, date_bounds
    WHERE DATE_FORMAT(InvoiceDate, '%Y-%m') = last_month
      AND CustomerID IS NOT NULL
      AND CustomerID <> 0
),

retained AS (
    SELECT c1.CustomerID
    FROM customers_first_month c1
    INNER JOIN customers_last_month c2
        ON c1.CustomerID = c2.CustomerID
),

churned AS (
    SELECT c1.CustomerID
    FROM customers_first_month c1
    LEFT JOIN customers_last_month c2
        ON c1.CustomerID = c2.CustomerID
    WHERE c2.CustomerID IS NULL
)

SELECT
    'retained' AS status_type,
    COUNT(*)   AS n_customers,
    ROUND(
        COUNT(*) / (SELECT COUNT(*) FROM customers_first_month),
        4
    )         AS percentage
FROM retained

UNION ALL

SELECT
    'churned' AS status_type,
    COUNT(*)  AS n_customers,
    ROUND(
        COUNT(*) / (SELECT COUNT(*) FROM customers_first_month),
        4
    )         AS percentage
FROM churned;



/* ================================================================
   ANALYSIS 4: Customer Revenue Contribution by Country
   ----------------------------------------------------------------
   - Aggregates customer-level revenue and net value by country
================================================================ */

WITH customer_sales AS (
    SELECT
        CustomerID,
        Country,
        SUM(Order_Value) AS total_sales_value
    FROM sales_classified
    WHERE 
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY CustomerID, Country
),

customer_returns AS (
    SELECT
        CustomerID,
        SUM(-Order_Value) AS total_returns_value
    FROM returns_classified
    GROUP BY CustomerID
),

customer_net AS (
    SELECT
        cs.CustomerID,
        cs.Country,
        cs.total_sales_value,
        COALESCE(cr.total_returns_value, 0) AS total_returns_value,
        cs.total_sales_value - COALESCE(cr.total_returns_value, 0) AS net_value
    FROM customer_sales cs
    LEFT JOIN customer_returns cr
        ON cs.CustomerID = cr.CustomerID
)

SELECT
    Country,
    COUNT(DISTINCT CustomerID)              AS n_customers,
    SUM(total_sales_value)                  AS total_sales_value,
    SUM(total_returns_value)                AS total_returns_value,
    SUM(net_value)                          AS total_net_value,
    ROUND(AVG(net_value), 2)                AS avg_net_value_per_customer
FROM customer_net
GROUP BY Country
ORDER BY total_net_value DESC;



/* ================================================================
   ANALYSIS 5: Monthly Active Customers
   ----------------------------------------------------------------
   - Distinct customers who purchased in each calendar month
================================================================ */

SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS YearMonth,
    COUNT(DISTINCT CustomerID)        AS active_customers
FROM sales_classified
WHERE 
    Financial_Type = 'revenue'
    AND CustomerID IS NOT NULL
    AND CustomerID <> 0
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY YearMonth;

/* ================================================================
   ANALYSIS 6: New vs Returning Customers (Monthly)
   ----------------------------------------------------------------
   - For each calendar month, classify active customers as:
       * NEW:   first-ever purchase happens in that month
       * RETURNING: purchased before and purchased again in that month
   - Outputs, per month:
       * active_customers
       * new_customers
       * returning_customers
       * share of new vs returning customers
================================================================ */

WITH customer_first_month AS (
    /* For each customer, find the month of their first purchase */
    SELECT
        CustomerID,
        DATE_FORMAT(MIN(InvoiceDate), '%Y-%m') AS first_month
    FROM sales_classified
    WHERE
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY CustomerID
),

month_activity AS (
    /* Distinct (month, customer) pairs = one active customer per month */
    SELECT
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS YearMonth,
        CustomerID
    FROM sales_classified
    WHERE
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY
        DATE_FORMAT(InvoiceDate, '%Y-%m'),
        CustomerID
)

SELECT
    ma.YearMonth,
    COUNT(*) AS active_customers,

    /* Customers whose first-ever month equals this month */
    SUM(CASE
            WHEN cf.first_month = ma.YearMonth THEN 1
            ELSE 0
        END) AS new_customers,

    /* Active customers minus the new ones = returning customers */
    COUNT(*) -
    SUM(CASE
            WHEN cf.first_month = ma.YearMonth THEN 1
            ELSE 0
        END) AS returning_customers,

    /* Shares as fractions of total active customers */
    ROUND(
        SUM(CASE WHEN cf.first_month = ma.YearMonth THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        4
    ) AS new_customer_share,

    ROUND(
        (COUNT(*) -
         SUM(CASE WHEN cf.first_month = ma.YearMonth THEN 1 ELSE 0 END))
        / NULLIF(COUNT(*), 0),
        4
    ) AS returning_customer_share

FROM month_activity ma
JOIN customer_first_month cf
    ON ma.CustomerID = cf.CustomerID
GROUP BY ma.YearMonth
ORDER BY ma.YearMonth;

/* ================================================================
   ANALYSIS 7: RFM Segmentation (Recency / Frequency / Monetary)
   ----------------------------------------------------------------
   - R (Recency):   Days since last purchase (lower is better)
   - F (Frequency): Number of distinct orders (higher is better)
   - M (Monetary):  Total revenue (higher is better)
   - Steps:
       1) Compute raw R, F, M for each customer
       2) Convert to R, F, M scores from 1 (worst) to 5 (best)
       3) Assign a segment label (Champion, Loyal, At Risk, etc.)
================================================================ */

-- 7.0: Create a reusable view with full RFM + segment labels
CREATE OR REPLACE VIEW rfm_segmented AS
WITH max_date AS (
    /* Latest invoice date in the dataset (used for recency) */
    SELECT MAX(InvoiceDate) AS max_invoice_date
    FROM sales_classified
    WHERE
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
),

rfm_base AS (
    /* Raw RFM values per customer */
    SELECT
        s.CustomerID,
        -- Frequency: number of distinct invoices
        COUNT(DISTINCT s.InvoiceNo) AS frequency,
        -- Monetary: total revenue
        SUM(s.Order_Value)          AS monetary,
        -- Recency: days since last purchase (lower = more recent)
        DATEDIFF(
            (SELECT max_invoice_date FROM max_date),
            MAX(s.InvoiceDate)
        )                           AS recency_days
    FROM sales_classified s
    WHERE
        s.Financial_Type = 'revenue'
        AND s.CustomerID IS NOT NULL
        AND s.CustomerID <> 0
    GROUP BY s.CustomerID
),

rfm_scored AS (
    /* Convert R, F, M into 1–5 scores using NTILE */
    SELECT
        rb.*,
        -- Recency: lower days = better → flip so 5 = best, 1 = worst
        6 - NTILE(5) OVER (ORDER BY rb.recency_days ASC) AS r_score,
        -- Frequency & Monetary: higher = better → 5 = best
        NTILE(5) OVER (ORDER BY rb.frequency DESC)       AS f_score,
        NTILE(5) OVER (ORDER BY rb.monetary DESC)        AS m_score
    FROM rfm_base rb
)

SELECT
    CustomerID,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score)      AS rfm_code,

    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champion'
        WHEN r_score >= 4 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal'
        WHEN r_score >= 3 AND f_score >= 4 AND m_score >= 4 THEN 'Big Spender'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score <= 2 THEN 'Potential Loyalist'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Churn Risk'
        ELSE 'Other'
    END AS segment_label
FROM rfm_scored;

/* 7.1 – Detailed customer-level RFM output */
SELECT
    CustomerID,
    recency_days,
    frequency,
    ROUND(monetary, 2)                AS monetary,
    r_score,
    f_score,
    m_score,
    rfm_code,
    segment_label
FROM rfm_segmented
ORDER BY
    segment_label,
    monetary DESC;

/* 7.2 – Segment distribution: how many customers in each segment */
SELECT
    segment_label,
    COUNT(*) AS n_customers,
    ROUND(
        COUNT(*) / (SELECT COUNT(*) FROM rfm_segmented),
        4
    ) AS percentage
FROM rfm_segmented
GROUP BY segment_label
ORDER BY n_customers DESC;


/* ================================================================
   ANALYSIS 8: Monthly Cohort Retention
   ----------------------------------------------------------------
   Goal:
   - Group customers into cohorts based on their FIRST purchase month
   - Track in which later months they come back and how many return
   - Compute a retention_rate per (cohort_month, month_index)

   Definitions:
   - cohort_month  = YYYY-MM of the customer's first-ever order
   - activity_month = YYYY-MM of any subsequent order
   - month_index   = 0 for cohort month, 1 for next month, etc.
================================================================ */

-- 8.1) Create (or replace) a view that stores full cohort retention table
CREATE OR REPLACE VIEW cohort_retention AS
WITH customer_first_month AS (
    /* Each customer's first purchase month = their cohort */
    SELECT
        CustomerID,
        DATE_FORMAT(MIN(InvoiceDate), '%Y-%m') AS cohort_month
    FROM sales_classified
    WHERE
        Financial_Type = 'revenue'
        AND CustomerID IS NOT NULL
        AND CustomerID <> 0
    GROUP BY CustomerID
),

customer_month_activity AS (
    /* All months in which a customer was active (made at least one purchase) */
    SELECT
        s.CustomerID,
        DATE_FORMAT(s.InvoiceDate, '%Y-%m') AS activity_month
    FROM sales_classified s
    WHERE
        s.Financial_Type = 'revenue'
        AND s.CustomerID IS NOT NULL
        AND s.CustomerID <> 0
    GROUP BY
        s.CustomerID,
        DATE_FORMAT(s.InvoiceDate, '%Y-%m')
),

cohort_activity AS (
    /* Join each customer’s cohort_month to each month they were active */
    SELECT
        cfm.CustomerID,
        cfm.cohort_month,
        cma.activity_month,
        -- convert to real dates so we can subtract months
        STR_TO_DATE(CONCAT(cfm.cohort_month, '-01'), '%Y-%m-%d')  AS cohort_date,
        STR_TO_DATE(CONCAT(cma.activity_month, '-01'), '%Y-%m-%d') AS activity_date
    FROM customer_first_month cfm
    JOIN customer_month_activity cma
        ON cfm.CustomerID = cma.CustomerID
),

cohort_activity_indexed AS (
    /* For each (cohort_month, activity_month), how many months since cohort start? */
    SELECT
        cohort_month,
        activity_month,
        TIMESTAMPDIFF(MONTH, cohort_date, activity_date) AS month_index,
        COUNT(DISTINCT CustomerID)                        AS active_customers
    FROM cohort_activity
    GROUP BY
        cohort_month,
        activity_month,
        month_index
),

cohort_sizes AS (
    /* Size of each cohort (how many customers joined in that month) */
    SELECT
        cohort_month,
        COUNT(DISTINCT CustomerID) AS cohort_size
    FROM customer_first_month
    GROUP BY cohort_month
)

SELECT
    cai.cohort_month,
    cai.activity_month,
    cai.month_index,          -- 0 = cohort month, 1 = next month, etc.
    cai.active_customers,
    cs.cohort_size,
    ROUND(
        cai.active_customers / NULLIF(cs.cohort_size, 0),
        4
    ) AS retention_rate
FROM cohort_activity_indexed cai
JOIN cohort_sizes cs
    ON cai.cohort_month = cs.cohort_month
ORDER BY
    cai.cohort_month,
    cai.month_index;


-- 8.2) Quick preview of the first few months of each cohort
SELECT
    cohort_month,
    month_index,
    active_customers,
    cohort_size,
    retention_rate
FROM cohort_retention
WHERE month_index <= 5
ORDER BY cohort_month, month_index;


-- 8.3) High-level retention summary across all cohorts
--     (Average retention at key lifecycle points)
SELECT 
    ROUND(AVG(CASE WHEN month_index = 1  THEN retention_rate END), 4) AS avg_m1_retention,
    ROUND(AVG(CASE WHEN month_index = 2  THEN retention_rate END), 4) AS avg_m2_retention,
    ROUND(AVG(CASE WHEN month_index = 3  THEN retention_rate END), 4) AS avg_m3_retention,
    ROUND(AVG(CASE WHEN month_index = 6  THEN retention_rate END), 4) AS avg_m6_retention,
    ROUND(AVG(CASE WHEN month_index = 12 THEN retention_rate END), 4) AS avg_m12_retention
FROM cohort_retention;
