/* =====================================================================
   SALES ANALYSIS
   ---------------------------------------------------------------------
   Part of: Retail Analytics & Returns Intelligence System
   Purpose:
     - Analyze sales performance over time
     - Identify top-performing products and countries
     - Understand product return rates and value impact
===================================================================== */


/* ================================================================
   ANALYSIS 1: Monthly Revenue Trend
   ----------------------------------------------------------------
   - Aggregates total revenue per calendar month
   - Includes only rows classified as Financial_Type = 'revenue'
================================================================ */

SELECT
    t.YEAR_NAME,
    t.MONTH_NAME,
    t.REVENUE
FROM (
    SELECT 
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS YEARMONTH,
        DATE_FORMAT(InvoiceDate, '%Y')    AS YEAR_NAME,
        DATE_FORMAT(InvoiceDate, '%M')    AS MONTH_NAME,
        SUM(Order_Value)                  AS REVENUE
    FROM sales_classified
    WHERE Financial_Type = 'revenue'
    GROUP BY 
        DATE_FORMAT(InvoiceDate, '%Y-%m'),
        DATE_FORMAT(InvoiceDate, '%Y'),
        DATE_FORMAT(InvoiceDate, '%M')
) AS t
ORDER BY t.YEARMONTH;



/* ================================================================
   ANALYSIS 2: Top 10 Best-Selling Products by Revenue
   ----------------------------------------------------------------
   - Uses cleaned product descriptions
   - Filters to:
       * Transaction_Category = 'product'
       * Financial_Type = 'revenue'
   - Ranks by revenue, highest first
================================================================ */

SELECT
    Description_clean,
    SUM(Quantity)     AS units_sold,
    SUM(Order_Value)  AS revenue
FROM sales_classified
WHERE
     Transaction_Category = 'product'
     AND Financial_Type = 'revenue'
     AND Order_Value > 0
GROUP BY Description_clean
ORDER BY revenue DESC
LIMIT 10;



/* ================================================================
   ANALYSIS 3: Top 5 Countries by Total Revenue
   ----------------------------------------------------------------
   - Aggregates total revenue by country
   - Helps identify key geographic markets
================================================================ */

SELECT 
    Country,
    SUM(Order_Value) AS revenue
FROM sales_classified
WHERE Financial_Type = 'revenue'
GROUP BY Country 
ORDER BY revenue DESC
LIMIT 5;



/* ================================================================
   ANALYSIS 4: Product-Level Return Rate (by quantity)
   ----------------------------------------------------------------
   - Joins sales and returns at StockCode level
   - Computes:
       * sold_qty      : total units sold
       * returned_qty  : total units returned
       * return_rate   : returned_qty / sold_qty
   - Filters to products with:
       * sold_qty >= 100
       * return_rate > 0
   - Useful to flag problematic products
================================================================ */

SELECT
    s.StockCode,
    s.Description_clean,
    SUM(s.Quantity) AS sold_qty,
    SUM(CASE WHEN r.Quantity < 0 THEN -r.Quantity ELSE 0 END) AS returned_qty,
    ROUND(
        SUM(CASE WHEN r.Quantity < 0 THEN -r.Quantity ELSE 0 END) /
        NULLIF(SUM(s.Quantity), 0), 4
    ) AS return_rate_qty
FROM sales_classified s
LEFT JOIN returns_classified r
    ON s.StockCode = r.StockCode
GROUP BY
    s.StockCode,
    s.Description_clean
HAVING
    sold_qty >= 100
    AND return_rate_qty > 0
ORDER BY return_rate_qty DESC
LIMIT 50;



/* ================================================================
   ANALYSIS 5: Monthly Return Rate (value-based)
   ----------------------------------------------------------------
   - Aggregates monthly:
       * sales_value   : total revenue
       * returns_value : total value of returns (as positive)
   - Computes:
       * return_rate_value = returns_value / sales_value
   - Shows whether returns are improving or worsening over time
================================================================ */

SELECT
    s.YearMonth,
    s.sales_value,
    COALESCE(r.returns_value, 0) AS returns_value,
    ROUND(
        COALESCE(r.returns_value, 0) / NULLIF(s.sales_value, 0),
        4
    ) AS return_rate_value
FROM (
    -- Monthly sales
    SELECT
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS YearMonth,
        SUM(Order_Value) AS sales_value
    FROM sales_classified
    WHERE Financial_Type = 'revenue'
    GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
) s
LEFT JOIN (
    -- Monthly returns (value)
    SELECT
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS YearMonth,
        SUM(-Order_Value) AS returns_value
    FROM returns_classified
    GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
) r
ON s.YearMonth = r.YearMonth
ORDER BY s.YearMonth;
