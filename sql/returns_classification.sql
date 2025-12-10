/* =====================================================================
   RETURNS CLASSIFICATION MODEL
   ---------------------------------------------------------------------
   Part of: Retail Analytics & Returns Intelligence System
   Purpose:
     - Build a semantic classification layer on top of the RETURNS view
     - Understand *why* items are returned and how they should be handled
       operationally and financially

   Output view: returns_classified

   Extra columns added:
     - IsDiscount              : flag for discount lines (StockCode = 'D')
     - customer_return_count   : total return lines per customer
     - day_net_quantity        : net quantity per customer per day
     - Return_Type             : high-level category of return
     - Return_Reason           : more specific reason
     - Refund_Status           : processing / review / fraud / pending status
===================================================================== */

USE inventory;


/* ================================================================
   Optional Diagnostics
   ----------------------------------------------------------------
   Explore which StockCodes appear in RETURNS to understand
   non-standard codes before classification logic is finalised.
=================================================================== */
SELECT COUNT(DISTINCT StockCode) AS distinct_return_stockcodes
FROM returns;

SELECT DISTINCT StockCode
FROM returns
ORDER BY StockCode;

SELECT DISTINCT StockCode
FROM returns
WHERE StockCode REGEXP '^[A-Za-z]+$';
/* Alphabetic-only codes, often non-product identifiers */


/* ================================================================
   Create returns_classified View
   ----------------------------------------------------------------
   Step 1: base CTE with helper metrics
   Step 2: classified CTE applying business rules
=================================================================== */

CREATE OR REPLACE VIEW returns_classified AS
WITH base AS (
    SELECT
        r.*,

        -- Flag discount codes
        (r.StockCode = 'D') AS IsDiscount,

        -- How many return lines this customer has in total
        COUNT(*) OVER (PARTITION BY r.CustomerID) AS customer_return_count,

        -- Net quantity per customer per day:
        -- if this sums to 0, it suggests the entire day's orders
        -- for that customer were cancelled out.
        SUM(r.Quantity) OVER (
            PARTITION BY r.CustomerID, DATE(r.InvoiceDate)
        ) AS day_net_quantity

    FROM returns r
),

classified AS (
    SELECT
        base.*,

        /* ---------------------------------------------------------
           1) Return_Type: high-level category of the return
           --------------------------------------------------------- */
        CASE
            -- Full-day cancellation (net quantity zero for that customer/day)
            WHEN day_net_quantity = 0 THEN 'cancellation'

            -- Explicit discount lines
            WHEN StockCode = 'D' THEN 'price_adjustment'

            -- Manual/system operations
            WHEN StockCode = 'M' THEN 'system_return'

            -- Shipping-related returns
            WHEN StockCode IN ('POST', 'DOT') THEN 'service_return'

            -- Damaged or defective goods
            WHEN Description_clean REGEXP 'DAMAGED|BROKEN|DEFECT'
                 AND StockCode NOT IN ('D','M')
                THEN 'damaged_goods'

            -- Manual override notes in description
            WHEN Description_clean REGEXP 'MANUAL|OVERRIDE'
                 AND StockCode NOT IN ('D','M')
                THEN 'system_return'

            -- Very large (high value) returns (non-discount)
            WHEN Order_Value < -500
                 AND StockCode NOT IN ('D','M')
                THEN 'customer_return'

            -- Default case: regular customer returns
            ELSE 'customer_return'
        END AS Return_Type,

        /* ---------------------------------------------------------
           2) Return_Reason: more detailed explanation
           --------------------------------------------------------- */
        CASE
            WHEN day_net_quantity = 0 THEN 'order_cancellation'

            WHEN StockCode = 'D' THEN
                CASE
                    -- Suspiciously large discounts (<= -500)
                    WHEN Order_Value <= -500 THEN 'suspicious_discount'
                    -- High-value discounts (<= -100)
                    WHEN Order_Value <= -100 THEN 'high_value_discount'
                    ELSE 'standard_discount'
                END

            WHEN StockCode = 'M' THEN 'manual_error'

            WHEN StockCode IN ('POST', 'DOT') THEN 'shipping_error'

            WHEN Description_clean REGEXP 'DAMAGED|BROKEN|DEFECT'
                 AND StockCode NOT IN ('D','M')
                THEN 'defective_product'

            WHEN Description_clean REGEXP 'MANUAL|OVERRIDE'
                 AND StockCode NOT IN ('D','M')
                THEN 'manual_override'

            WHEN Order_Value < -500
                 AND StockCode NOT IN ('D','M')
                THEN 'high_value'

            WHEN customer_return_count > 5
                 AND StockCode NOT IN ('D','M')
                THEN 'frequent_returner'

            ELSE 'unsatisfied'
        END AS Return_Reason,

        /* ---------------------------------------------------------
           3) Refund_Status: workflow / approval status
           --------------------------------------------------------- */
        CASE
            -- Cancellation: non-discount lines are auto-processed
            WHEN day_net_quantity = 0 AND StockCode <> 'D'
                THEN 'processed'

            -- Suspicious discounts → fraud review
            WHEN StockCode = 'D' AND Order_Value <= -500
                THEN 'fraud_review'

            -- High-value discounts → need approval
            WHEN StockCode = 'D' AND Order_Value <= -100
                THEN 'pending_approval'

            -- Auto-approved discounts (loyalty/contract/bulk) by description keywords
            WHEN StockCode = 'D'
                 AND (Description_clean LIKE '%LOYALTY%'
                      OR Description_clean LIKE '%CONTRACT%'
                      OR Description_clean LIKE '%BULK%')
                THEN 'processed'

            -- Manual system returns are pending
            WHEN StockCode = 'M'
                THEN 'pending'

            -- Returns with manual override text also pending
            WHEN Description_clean REGEXP 'MANUAL|OVERRIDE'
                 AND StockCode NOT IN ('D','M')
                THEN 'pending'

            -- Very large non-discount returns → review
            WHEN Order_Value < -500
                 AND StockCode NOT IN ('D','M')
                THEN 'pending_review'

            -- Frequent returners → special review
            WHEN customer_return_count > 5
                 AND StockCode NOT IN ('D','M')
                THEN 'review_required'

            -- Default: processed normally
            ELSE 'processed'
        END AS Refund_Status

    FROM base
)

SELECT *
FROM classified;
-- end of view definition


/* ================================================================
   Validation: summarize classification distribution
   ----------------------------------------------------------------
   Quick QA to see how many rows fall into each combination of:
     - Return_Type
     - Return_Reason
     - Refund_Status
=================================================================== */

SELECT
    Return_Type,
    Return_Reason,
    Refund_Status,
    COUNT(*)        AS n_rows,
    MIN(Order_Value) AS min_val,
    MAX(Order_Value) AS max_val
FROM returns_classified
GROUP BY
    Return_Type,
    Return_Reason,
    Refund_Status
ORDER BY
    Return_Type,
    Return_Reason,
    Refund_Status;
