-- 01_clean.sql  |  Extract & clean raw transactions  (SQLite dialect)
-- Input : raw_sales   (loaded from data/sales_raw.csv by R/01_build_db.R)
-- Output: sales_clean, cleaning_audit

DROP TABLE IF EXISTS sales_clean;

CREATE TABLE sales_clean AS
WITH dedup AS (                       -- 1. remove exact duplicate lines
    SELECT DISTINCT * FROM raw_sales
),
standardised AS (                     -- 2. standardise text + dates
    SELECT
        order_id,
        CASE WHEN order_date LIKE '__/__/____'            -- dd/mm/yyyy -> ISO
             THEN substr(order_date,7,4)||'-'||substr(order_date,4,2)||'-'||substr(order_date,1,2)
             ELSE order_date END                                   AS order_date,
        ship_date,
        customer_id,
        customer_name,
        segment,
        CASE UPPER(TRIM(region))
             WHEN 'WEST' THEN 'West'   WHEN 'EAST' THEN 'East'
             WHEN 'CENTRAL' THEN 'Central' WHEN 'SOUTH' THEN 'South' END AS region,
        state,
        CASE LOWER(TRIM(category))
             WHEN 'furniture' THEN 'Furniture'
             WHEN 'office supplies' THEN 'Office Supplies'
             WHEN 'technology' THEN 'Technology' END               AS category,
        sub_category,
        product_name,
        sales,
        quantity,
        COALESCE(discount, 0)                                      AS discount,
        CASE WHEN discount IS NULL THEN 1 ELSE 0 END               AS discount_imputed,
        profit,
        ship_mode
    FROM dedup
)
SELECT
    *,
    CAST(substr(order_date,1,4) AS INTEGER)                        AS order_year,
    CAST(substr(order_date,6,2) AS INTEGER)                        AS order_month,
    substr(order_date,1,7)                                         AS year_month,
    ROUND(sales / quantity, 2)                                     AS unit_net_price,
    ROUND(sales - profit, 2)                                       AS cost,
    CASE WHEN discount = 0            THEN '0%'
         WHEN discount <= 0.2         THEN '1-20%'
         WHEN discount <= 0.3         THEN '21-30%'
         WHEN discount <= 0.5         THEN '31-50%'
         ELSE '>50%' END                                           AS discount_band
FROM standardised
WHERE sales    IS NOT NULL         -- 3. drop rows that cannot be analysed
  AND quantity > 0
  AND sales    > 0
  AND region   IS NOT NULL
  AND category IS NOT NULL;

CREATE INDEX idx_sc_ym   ON sales_clean(year_month);
CREATE INDEX idx_sc_cust ON sales_clean(customer_id);

-- Audit trail so every cleaning step is quantified
DROP TABLE IF EXISTS cleaning_audit;
CREATE TABLE cleaning_audit AS
SELECT 'raw rows'                         AS step, COUNT(*) AS n FROM raw_sales
UNION ALL SELECT 'after de-duplication',            COUNT(*) FROM (SELECT DISTINCT * FROM raw_sales)
UNION ALL SELECT 'clean rows kept',                 COUNT(*) FROM sales_clean
UNION ALL SELECT 'discount imputed to 0 (flagged)', SUM(discount_imputed) FROM sales_clean;
