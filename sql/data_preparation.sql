/* =====================================================================
   DATA PREPARATION & BASE MODELING
   ---------------------------------------------------------------------
   Part of: Retail Analytics & Returns Intelligence System
   Purpose:
     - Load and inspect raw cleaned dataset
     - Create core views: SALES, RETURNS, SALES_DATED
     - Prepare structured inputs for classification and analytics modules
===================================================================== */


/* ================================================================
   Step 1: Select Target Database
================================================================ */
USE inventory;


/* ================================================================
   Step 2: Sanity Checks
   - List available tables
   - Preview the cleaned source table
================================================================ */
SHOW TABLES;

SELECT *
FROM clean_transactions
LIMIT 10;


/* ================================================================
   Step 3: Create SALES View
   ----------------------------------------------------------------
   Description:
     - Extract only positive quantities (actual sales transactions)
     - Use cleaned description field
     - Used as the foundation for product, sales, and customer analysis
================================================================ */
CREATE OR REPLACE VIEW sales AS
SELECT
    InvoiceNo,
    InvoiceDate,
    StockCode,
    Description_clean,
    Quantity,
    UnitPrice,
    Order_Value,
    CustomerID,
    Country,
    Customertype
FROM clean_transactions
WHERE Quantity > 0;


/* ================================================================
   Step 4: Create RETURNS View
   ----------------------------------------------------------------
   Description:
     - Extract only negative quantities (returns/refunds)
     - Matches the structure of SALES for easy joins & analysis
================================================================ */
CREATE OR REPLACE VIEW returns AS
SELECT
    InvoiceNo,
    InvoiceDate,
    StockCode,
    Description_clean,
    Quantity,
    UnitPrice,
    Order_Value,
    CustomerID,
    Country,
    Customertype
FROM clean_transactions
WHERE Quantity < 0;


/* ================================================================
   Step 5: Base Row Counts
   ----------------------------------------------------------------
   Quick verification to compare volume of sales vs returns.
================================================================ */
SELECT COUNT(*) AS sales_rows FROM sales;
SELECT COUNT(*) AS return_rows FROM returns;


/* ================================================================
   Step 6: Create SALES_DATED View
   ----------------------------------------------------------------
   Description:
     - Enrich sales with date parts for time-series analysis
     - Adds: invoice_date, year, month, month label, weekday, quarter
     - Supports monthly trends, seasonality, customer activity tracking
================================================================ */
CREATE OR REPLACE VIEW sales_dated AS
SELECT 
   s.*,
   DATE(InvoiceDate)                  AS invoice_date,
   YEAR(InvoiceDate)                  AS invoice_year,
   MONTH(InvoiceDate)                 AS invoice_month,
   DATE_FORMAT(InvoiceDate, '%Y-%M')  AS invoice_year_month,
   DAYOFWEEK(InvoiceDate)             AS invoice_weekday,
   QUARTER(InvoiceDate)               AS invoice_quarter
FROM sales AS s;


/* ================================================================
   Step 7: Preview the Enriched Sales View
================================================================ */
SELECT *
FROM sales_dated
ORDER BY RAND()
LIMIT 10;
