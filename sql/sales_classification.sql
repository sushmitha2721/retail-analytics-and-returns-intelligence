/* =====================================================================
   SALES CLASSIFICATION MODEL
   ---------------------------------------------------------------------
   Part of: Retail Analytics & Returns Intelligence System
   Purpose:
     - Add a semantic classification layer on top of the SALES view
     - Categorize each sales transaction into:
         * Transaction_Category  (product / service / adjustment)
         * Product_Type          (regular / shipping / samples / fees / etc.)
         * Financial_Type        (revenue / fee / adjustment / non_revenue)
     - Standardize transaction meaning for downstream KPIs and analytics
===================================================================== */

USE inventory;


/* ================================================================
   Step 1: Inspect StockCodes that are non-product identifiers
   ----------------------------------------------------------------
   Purpose:
     - Understand which alphabetic codes represent shipping, fees,
       adjustments, manual corrections, or samples.
=================================================================== */
SELECT DISTINCT StockCode
FROM sales
WHERE StockCode REGEXP '^[A-Za-z]+$';


/* ================================================================
   Step 2: Create sales_classified View
   ----------------------------------------------------------------
   Adds classification logic including:
     - B, M → adjustments / corrections
     - POST, DOT, AMAZONFEE, C2 → shipping & service fees
     - S → samples (free or paid)
     - Everything else → standard product revenue
=================================================================== */

CREATE OR REPLACE VIEW sales_classified AS
SELECT
    s.*,

    /* ---------------------------------------------------------
       1) Transaction_Category
       High-level grouping of transaction purpose
       --------------------------------------------------------- */
    CASE
        WHEN s.StockCode = 'B' THEN 'adjustment'               -- bad debt / write-off
        WHEN s.StockCode = 'M' THEN 'adjustment'               -- manual correction
        WHEN s.StockCode IN ('POST', 'DOT', 'AMAZONFEE', 'C2')
            THEN 'service'                                     -- shipping / delivery / fees
        WHEN s.StockCode = 'S' AND s.Order_Value = 0
            THEN 'adjustment'                                  -- free sample → no revenue
        ELSE 'product'                                         -- standard sale
    END AS Transaction_Category,


    /* ---------------------------------------------------------
       2) Product_Type
       More specific subtype describing the item
       --------------------------------------------------------- */
    CASE
        WHEN s.StockCode = 'B' THEN 'bad_debt'
        WHEN s.StockCode = 'M' THEN 'manual'
        WHEN s.StockCode = 'POST' THEN 'domestic_shipping'
        WHEN s.StockCode = 'DOT'  THEN 'international_shipping'
        WHEN s.StockCode = 'AMAZONFEE' THEN 'amazon_fee'
        WHEN s.StockCode = 'C2' THEN 'special_carriage'
        WHEN s.StockCode = 'PADS' THEN 'accessory'
        WHEN s.StockCode = 'S' AND s.Order_Value > 0 THEN 'paid_sample'
        WHEN s.StockCode = 'S' AND s.Order_Value = 0 THEN 'free_sample'
        ELSE 'regular'                                          -- typical product line
    END AS Product_Type,


    /* ---------------------------------------------------------
       3) Financial_Type
       Defines how each row impacts financial reporting
       --------------------------------------------------------- */
    CASE
        WHEN s.StockCode = 'B' THEN 'adjustment'               -- reduces revenue
        WHEN s.StockCode IN ('POST', 'DOT', 'AMAZONFEE', 'C2')
            THEN 'fee'                                         -- service charges
        WHEN s.StockCode = 'S' AND s.Order_Value = 0
            THEN 'non_revenue'                                 -- free samples
        ELSE 'revenue'                                          -- standard product income
    END AS Financial_Type

FROM sales AS s;


/* ================================================================
   Step 3: Validation Summary
   ----------------------------------------------------------------
   Purpose:
     - Verify classification accuracy
     - View row counts and value ranges per category
=================================================================== */

SELECT
    Transaction_Category,
    Product_Type,
    Financial_Type,
    COUNT(*) AS n_rows,
    MIN(Order_Value) AS min_val,
    MAX(Order_Value) AS max_val
FROM sales_classified
GROUP BY Transaction_Category, Product_Type, Financial_Type
ORDER BY Transaction_Category, Product_Type;
