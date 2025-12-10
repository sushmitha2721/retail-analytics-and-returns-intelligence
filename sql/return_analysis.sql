/* =====================================================================
   RETURNS ANALYSIS
   ---------------------------------------------------------------------
   Part of: Retail Analytics & Returns Intelligence System
   Purpose:
     - Quantify total returns (quantity and value)
     - Understand return patterns by type, reason, and status
     - Analyse geographic impact of returns
     - Identify products with the highest return volumes
===================================================================== */


/* ================================================================
   ANALYSIS 1: Total Returns (Quantity + Value)
   ----------------------------------------------------------------
   - Aggregates total returned quantity and value across the dataset
   - Uses returns_classified (returns-only, negative quantities)
================================================================ */

SELECT
    'returns' AS metric_type,
    SUM(-Quantity)    AS total_return_qty,      -- positive quantity
    SUM(-Order_Value) AS total_return_value     -- positive value
FROM returns_classified;



/* ================================================================
   ANALYSIS 2: Returns Breakdown by Return_Type
   ----------------------------------------------------------------
   - Grouped by Return_Type classification:
       * customer_return
       * price_adjustment
       * service_return
       * system_return
       * damaged_goods
   - Shows:
       * number of transactions
       * total return value (negative + absolute)
       * average return value
================================================================ */

SELECT
    Return_Type,
    COUNT(*)                           AS n_transactions,
    SUM(Order_Value)                   AS total_return_value,       -- negative
    SUM(-Order_Value)                  AS total_return_value_abs,   -- positive
    ROUND(AVG(Order_Value), 2)         AS avg_return_value
FROM returns_classified
GROUP BY Return_Type
ORDER BY total_return_value ASC;   -- most negative (worst impact) first



/* ================================================================
   ANALYSIS 3: Return Reasons & Refund Status
   ----------------------------------------------------------------
   - Breaks down returns by:
       * Return_Type       : what kind of return
       * Return_Reason     : why it happened
       * Refund_Status     : workflow state (processed / pending / review)
   - Useful for operational efficiency and fraud / risk insights
================================================================ */

SELECT
    Return_Type,
    Return_Reason,
    Refund_Status,
    COUNT(*)                       AS n_transactions,
    SUM(-Order_Value)              AS total_return_value_abs,
    ROUND(AVG(-Order_Value), 2)    AS avg_return_value_abs
FROM returns_classified
GROUP BY
    Return_Type,
    Return_Reason,
    Refund_Status
ORDER BY
    total_return_value_abs DESC;   -- largest loss first



/* ================================================================
   ANALYSIS 4: Returns by Country
   ----------------------------------------------------------------
   - Aggregates return volume and value by customer country
   - Can be compared with sales by country to understand
     net performance per region
================================================================ */

SELECT
    Country,
    COUNT(*)          AS n_return_transactions,
    SUM(-Order_Value) AS total_return_value_abs
FROM returns_classified
GROUP BY Country
ORDER BY total_return_value_abs DESC;   -- highest return value first



/* ================================================================
   ANALYSIS 5: Most Returned Products (by Quantity)
   ----------------------------------------------------------------
   - Identifies products with the highest returned quantities
   - Helps inventory teams reduce stock of problematic items or
     investigate quality / fit / description issues
================================================================ */

SELECT
    StockCode,
    Description_clean,
    SUM(-Quantity) AS total_return_qty
FROM returns_classified
-- returns_classified already contains only negative quantities,
-- but this WHERE clause makes the intent explicit
WHERE Quantity < 0
GROUP BY StockCode, Description_clean
ORDER BY total_return_qty DESC
LIMIT 20;   -- top 20 most returned items
