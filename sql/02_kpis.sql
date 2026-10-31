-- 02_kpis.sql  |  Business KPI views  (SQLite >= 3.25 for window functions)

-- Monthly performance -------------------------------------------------------
DROP VIEW IF EXISTS v_monthly;
CREATE VIEW v_monthly AS
SELECT year_month, order_year, order_month,
       ROUND(SUM(sales),2)                          AS sales,
       ROUND(SUM(profit),2)                         AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales),2)        AS margin_pct,
       COUNT(DISTINCT order_id)                     AS orders,
       SUM(quantity)                                AS units,
       ROUND(AVG(discount)*100,2)                   AS avg_discount_pct
FROM sales_clean GROUP BY year_month;

-- Yearly performance + YoY growth ------------------------------------------
DROP VIEW IF EXISTS v_yearly;
CREATE VIEW v_yearly AS
WITH y AS (
  SELECT order_year,
         SUM(sales) AS sales, SUM(profit) AS profit,
         COUNT(DISTINCT order_id) AS orders, COUNT(DISTINCT customer_id) AS customers
  FROM sales_clean GROUP BY order_year)
SELECT order_year,
       ROUND(sales,2) AS sales, ROUND(profit,2) AS profit,
       ROUND(100.0*profit/sales,2) AS margin_pct,
       orders, customers,
       ROUND(sales/orders,2) AS avg_order_value,
       ROUND(100.0*(sales - LAG(sales) OVER (ORDER BY order_year)) / LAG(sales) OVER (ORDER BY order_year),2) AS sales_growth_pct,
       ROUND(100.0*(profit - LAG(profit) OVER (ORDER BY order_year)) / LAG(profit) OVER (ORDER BY order_year),2) AS profit_growth_pct
FROM y;

-- Category / sub-category ---------------------------------------------------
DROP VIEW IF EXISTS v_category;
CREATE VIEW v_category AS
SELECT category, sub_category,
       ROUND(SUM(sales),2) AS sales, ROUND(SUM(profit),2) AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales),2) AS margin_pct,
       ROUND(AVG(discount)*100,1) AS avg_discount_pct,
       SUM(quantity) AS units,
       ROUND(100.0*SUM(sales)/(SELECT SUM(sales) FROM sales_clean),1) AS sales_share_pct,
       RANK() OVER (ORDER BY SUM(profit) DESC) AS profit_rank
FROM sales_clean GROUP BY category, sub_category;

-- Region & region x category -----------------------------------------------
DROP VIEW IF EXISTS v_region;
CREATE VIEW v_region AS
SELECT region,
       ROUND(SUM(sales),2) AS sales, ROUND(SUM(profit),2) AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales),2) AS margin_pct,
       ROUND(AVG(discount)*100,1) AS avg_discount_pct,
       COUNT(DISTINCT customer_id) AS customers
FROM sales_clean GROUP BY region;

DROP VIEW IF EXISTS v_region_category;
CREATE VIEW v_region_category AS
SELECT region, category,
       ROUND(SUM(sales),2) AS sales, ROUND(SUM(profit),2) AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales),2) AS margin_pct
FROM sales_clean GROUP BY region, category;

-- Regional growth by year (window function) --------------------------------
DROP VIEW IF EXISTS v_region_growth;
CREATE VIEW v_region_growth AS
WITH r AS (SELECT region, order_year, SUM(sales) AS sales FROM sales_clean GROUP BY region, order_year)
SELECT region, order_year, ROUND(sales,2) AS sales,
       ROUND(100.0*(sales - LAG(sales) OVER (PARTITION BY region ORDER BY order_year))
             / LAG(sales) OVER (PARTITION BY region ORDER BY order_year),2) AS yoy_pct
FROM r;

-- Discount impact -----------------------------------------------------------
DROP VIEW IF EXISTS v_discount;
CREATE VIEW v_discount AS
SELECT discount_band,
       COUNT(*) AS lines,
       ROUND(SUM(sales),2) AS sales, ROUND(SUM(profit),2) AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales),2) AS margin_pct,
       ROUND(100.0*SUM(CASE WHEN profit<0 THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_lines_loss_making,
       ROUND(SUM(CASE WHEN profit<0 THEN profit ELSE 0 END),2) AS total_losses
FROM sales_clean WHERE discount_imputed = 0
GROUP BY discount_band;

-- Customer value (RFM-style) -------------------------------------------------
DROP VIEW IF EXISTS v_customer;
CREATE VIEW v_customer AS
WITH c AS (
  SELECT customer_id, segment, region,
         COUNT(DISTINCT order_id) AS frequency,
         ROUND(SUM(sales),2) AS monetary, ROUND(SUM(profit),2) AS profit,
         MAX(order_date) AS last_order,
         CAST(julianday((SELECT MAX(order_date) FROM sales_clean)) - julianday(MAX(order_date)) AS INTEGER) AS recency_days
  FROM sales_clean GROUP BY customer_id)
SELECT *,
       NTILE(5) OVER (ORDER BY monetary DESC) AS value_quintile
FROM c;

DROP VIEW IF EXISTS v_segment;
CREATE VIEW v_segment AS
SELECT segment,
       COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(sales),2) AS sales, ROUND(SUM(profit),2) AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales),2) AS margin_pct,
       ROUND(SUM(sales)/COUNT(DISTINCT order_id),2) AS avg_order_value
FROM sales_clean GROUP BY segment;

-- Seasonality index: avg month share of annual sales -------------------------
DROP VIEW IF EXISTS v_seasonality;
CREATE VIEW v_seasonality AS
WITH m AS (SELECT order_year, order_month, SUM(sales) AS s FROM sales_clean GROUP BY order_year, order_month),
     t AS (SELECT order_year, SUM(s) AS ys FROM m GROUP BY order_year)
SELECT order_month, ROUND(AVG(100.0*s/ys),2) AS avg_share_of_year_pct
FROM m JOIN t USING(order_year) GROUP BY order_month;

-- Loss-making lines driven by discounting (hand-off to R scenario analysis) ---
DROP VIEW IF EXISTS v_loss_makers;
CREATE VIEW v_loss_makers AS
SELECT category, sub_category, region, discount_band,
       COUNT(*) AS lines, ROUND(SUM(sales),2) AS sales, ROUND(SUM(profit),2) AS profit
FROM sales_clean WHERE profit < 0 AND discount_imputed = 0
GROUP BY category, sub_category, region, discount_band;
