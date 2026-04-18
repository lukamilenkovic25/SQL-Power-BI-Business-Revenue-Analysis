/* =========================================================
   PROJECT: SQL Business Analysis – Customer Revenue & Pareto
   PURPOSE: Analyze customer contribution to total revenue
   AUTHOR: Luka
   ========================================================= */


-- Check available tables
SELECT name
FROM sqlite_master
WHERE type = 'table';


SELECT COUNT(*)
FROM orders o
JOIN order_items oi
  ON o.order_id = oi.order_id;
  
SELECT *
FROM order_items
LIMIT 10;


/* ---------------------------------------------------------
   VIEW: Data Preparation
   Create a clean view for order items revenue
   --------------------------------------------------------- */

CREATE VIEW order_items_clean AS
SELECT
    order_id,
    product_id,
    quantity,
    CAST(
        REPLACE(
            REPLACE(revenue, '$', ''),
            '.', ''
        ) AS INTEGER
    ) AS revenue_clean
FROM order_items;

/* =========================================================
   VIEW: orders_clean
   PURPOSE: Normalize mixed date formats into ISO (YYYY-MM-DD)
   ========================================================= */

CREATE VIEW orders_clean AS
SELECT
    order_id,
    customer_id,
    order_date AS order_date_raw,

    CASE
        -- Already ISO format
        WHEN order_date LIKE '____-__-__'
            THEN DATE(order_date)

        -- Dot-separated date (D.M.YYYY or DD.MM.YYYY)
        WHEN order_date LIKE '%.%.%'
            THEN DATE(
                SUBSTR(order_date, LENGTH(order_date) - 3, 4) || '-' ||
                printf('%02d',
                    CAST(
                        SUBSTR(
                            order_date,
                            INSTR(order_date, '.') + 1,
                            LENGTH(order_date) - INSTR(order_date, '.') - 5
                        ) AS INTEGER
                    )
                ) || '-' ||
                printf('%02d',
                    CAST(
                        SUBSTR(order_date, 1, INSTR(order_date, '.') - 1)
                        AS INTEGER
                    )
                )
            )

        ELSE NULL
    END AS order_date_clean
FROM orders;

/* ---------------------------------------------------------
   STEP 1: Calculate total revenue per customer
   --------------------------------------------------------- */

WITH customer_revenue AS (
    SELECT
        c.customer_id,
        c.customer_name,
        SUM(oi.revenue_clean) AS total_revenue
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    JOIN order_items_clean oi
        ON o.order_id = oi.order_id
    GROUP BY
 		c.customer_id,
        c.customer_name
)
SELECT *
FROM customer_revenue
ORDER BY total_revenue DESC;

/* ---------------------------------------------------------
   STEP 2: Pareto analysis – cumulative revenue share
   --------------------------------------------------------- */

WITH customer_revenue AS (
    SELECT
        c.customer_id,
        c.customer_name,
        SUM(oi.revenue_clean) AS total_revenue
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    JOIN order_items_clean oi
        ON o.order_id = oi.order_id
    GROUP BY
        c.customer_id,
        c.customer_name
),
ranked_customers AS (
	SELECT
        customer_id,
        customer_name,
        total_revenue,
        SUM(total_revenue) OVER () AS overall_revenue,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
        ) AS cumulative_revenue
    FROM customer_revenue
)
SELECT
    customer_id,
    customer_name,
    total_revenue,
	ROUND(
        cumulative_revenue * 1.0 / overall_revenue,
        4
    ) AS cumulative_share
FROM ranked_customers
ORDER BY total_revenue DESC;

/* ---------------------------------------------------------
   STEP 3: Identify top customers contributing ~80% of revenue
   --------------------------------------------------------- */

WITH customer_revenue AS (
    SELECT
        c.customer_id,
        c.customer_name,
        SUM(oic.revenue_clean) AS total_revenue
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    JOIN order_items_clean oic
        ON o.order_id = oic.order_id
    GROUP BY
        c.customer_id,
        c.customer_name
),
ranked_customers AS (
    SELECT
        customer_id,
        customer_name,
        total_revenue,
        SUM(total_revenue) OVER () AS overall_revenue,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
        ) AS cumulative_revenue
    FROM customer_revenue
)
SELECT
    customer_id,
    customer_name,
    total_revenue
FROM ranked_customers
WHERE cumulative_revenue * 1.0 / overall_revenue <= 0.8
ORDER BY total_revenue DESC;

/* ---------------------------------------------------------
   STEP 4: Monthly revenue trend
   --------------------------------------------------------- */   

SELECT
    strftime('%Y', oc.order_date_clean) AS year,
    strftime('%m', oc.order_date_clean) AS month,
    SUM(oic.revenue_clean) AS monthly_revenue
FROM orders_clean oc
JOIN order_items_clean oic
    ON oc.order_id = oic.order_id
WHERE oc.order_date_clean IS NOT NULL
GROUP BY
    year,
    month
ORDER BY
    year,
    month;
/* ---------------------------------------------------------
   STEP 5: Year-over-Year monthly revenue comparison
   --------------------------------------------------------- */

WITH monthly_revenue AS (
    SELECT
        strftime('%Y', oc.order_date_clean) AS year,
        strftime('%m', oc.order_date_clean) AS month,
        SUM(oic.revenue_clean) AS revenue
    FROM orders_clean oc
    JOIN order_items_clean oic
        ON oc.order_id = oic.order_id
    WHERE oc.order_date_clean IS NOT NULL
    GROUP BY
        year,
        month
),
yoy AS (
    SELECT
        m2025.month,
        m2025.revenue AS revenue_2025,
        m2024.revenue AS revenue_2024,
        (m2025.revenue - m2024.revenue) AS yoy_change,
        ROUND(
            (m2025.revenue - m2024.revenue) * 1.0 / m2024.revenue,
            4
        ) AS yoy_growth_pct
    FROM monthly_revenue m2025
    JOIN monthly_revenue m2024
        ON m2025.month = m2024.month
       AND m2025.year = '2025'
       AND m2024.year = '2024'
)
SELECT *
FROM yoy
ORDER BY month;

``


/* =========================================================
   FINAL ANALYTICAL VIEWS
   Purpose: Clean semantic layer for Power BI consumption
   ========================================================= */

/* =========================================================
   VIEW: vw_monthly_revenue 
   ========================================================= */

CREATE VIEW vw_monthly_revenue AS
SELECT
    strftime('%Y', oc.order_date_clean) AS year,
    strftime('%m', oc.order_date_clean) AS month,
    SUM(oic.revenue_clean) AS monthly_revenue
FROM orders_clean oc
JOIN order_items_clean oic
    ON oc.order_id = oic.order_id
WHERE oc.order_date_clean IS NOT NULL
GROUP BY
    year,
    month;

/* =========================================================
   VIEW: vw_customer_revenue 
   ========================================================= */
   
CREATE VIEW vw_customer_revenue AS
SELECT
    c.customer_id,
    c.customer_name,
    SUM(oic.revenue_clean) AS total_revenue
FROM customers c
JOIN orders_clean oc
    ON c.customer_id = oc.customer_id
JOIN order_items_clean oic
    ON oc.order_id = oic.order_id
WHERE oc.order_date_clean IS NOT NULL
GROUP BY
    c.customer_id,
    c.customer_name;

/* =========================================================
   VIEW: vw_yoy_revenue
   ========================================================= */

CREATE VIEW vw_yoy_revenue AS
WITH monthly AS (
    SELECT
        strftime('%Y', oc.order_date_clean) AS year,
        strftime('%m', oc.order_date_clean) AS month,
        SUM(oic.revenue_clean) AS revenue
    FROM orders_clean oc
    JOIN order_items_clean oic
        ON oc.order_id = oic.order_id
    WHERE oc.order_date_clean IS NOT NULL
    GROUP BY
        year,
        month
)
SELECT
    m2025.month,
    m2025.revenue AS revenue_2025,
    m2024.revenue AS revenue_2024,
    (m2025.revenue - m2024.revenue) AS yoy_change,
    ROUND(
        (m2025.revenue - m2024.revenue) * 1.0 / m2024.revenue,
        4
    ) AS yoy_growth_pct
FROM monthly m2025
JOIN monthly m2024
    ON m2025.month = m2024.month
   AND m2025.year = '2025'
   AND m2024.year = '2024';



SELECT * FROM vw_monthly_revenue;
SELECT * FROM vw_yoy_revenue;
SELECT * FROM vw_customer_revenue;









