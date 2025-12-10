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
