
/*
===============================================================================
DDL Script: Create Gold Views
===============================================================================

Script Purpose:
    This script creates views for the Gold layer in the data warehouse.
    The Gold layer represents the final dimension and fact tables (Star Schema).

    Each view performs transformations and combines data from the Silver layer
    to produce a clean, enriched, and business-ready dataset.

Usage:
    These views can be queried directly for analytics and reporting.

===============================================================================
*/


-- =============================================================================
-- Create Dimension: gold.dim_customers
-- =============================================================================

--SELECT customer_id, COUNT(*) Duplicates FROM (
IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO

CREATE VIEW gold.dim_customers AS 
SELECT
    -- Generate surrogate key for each customer
    ROW_NUMBER() OVER (ORDER BY cst_id) AS customer_key,

    ci.cst_id AS customer_id,
    ci.cst_key AS customer_number,
    ci.cst_firstname AS first_name,
    ci.cst_lastname AS last_name,
    la.cntry AS country,
    ci.cst_marital_status AS marital_status,

    -- CRM is the master source for gender information
    CASE 
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END AS gender,

    ca.bdate AS birthdate,
    ci.cst_create_date AS create_date

FROM silver.crm_cust_info ci

LEFT JOIN silver.erp_cust_az12 ca
    ON ci.cst_key = ca.cid

LEFT JOIN silver.erp_loc_a101 la
    ON ci.cst_key = la.cid;
GO

--) t
--GROUP BY customer_id
--HAVING COUNT(*) > 1


/*
SELECT * FROM silver.erp_cust_az12;
SELECT * FROM silver.erp_loc_a101;
*/


/*
SELECT DISTINCT
    ci.cst_gndr,
    ca.gen,
    CASE 
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END AS new_gen
FROM silver.crm_cust_info ci

LEFT JOIN silver.erp_cust_az12 ca
    ON ci.cst_key = ca.cid

LEFT JOIN silver.erp_loc_a101 la
    ON ci.cst_key = la.cid;
*/


/*
SELECT * FROM gold.dim_customers;

SELECT DISTINCT gender
FROM gold.dim_customers;
*/


-- =============================================================================
-- Create Dimension: gold.dim_products
-- =============================================================================

--SELECT product_key, COUNT(*) AS Duplicates FROM (

IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT
    -- Generate surrogate key for each current product
    ROW_NUMBER() OVER (ORDER BY prd_start_dt, prd_key) AS product_key,

    pn.prd_id AS product_id,
    pn.prd_key AS product_number,
    pn.prd_nm AS product_name,
    pn.cat_id AS category_id,
    pc.cat AS category,
    pc.subcat AS subcategory,
    pc.maintenance,
    pn.prd_cost AS cost,
    pn.prd_line AS product_line,
    pn.prd_start_dt AS start_date

    -- pn.prd_end_dt AS end_date
    -- Not needed because only current products are selected

FROM silver.crm_prd_info pn

LEFT JOIN silver.erp_px_cat_g1v2 pc
    ON pn.cat_id = pc.id

-- Keep only the current version of each product
-- Historical records have an end date, while the current record has NULL
WHERE pn.prd_end_dt IS NULL;
-- ) t
-- GROUP BY product_key
-- HAVING COUNT(*) > 1
GO


/*
SELECT * FROM silver.crm_prd_info;
SELECT * FROM silver.erp_px_cat_g1v2;
*/

--SELECT * FROM gold.dim_products;


-- =============================================================================
-- Create Fact View: gold.fact_sales
-- =============================================================================

-- Build the sales fact view and replace original customer/product IDs
-- with surrogate keys from the Gold dimension views

--SELECT product_key, COUNT(*) AS Duplicates FROM (

IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO

CREATE VIEW gold.fact_sales AS 
SELECT
    sd.sls_ord_num AS order_number,

    -- Use surrogate product key instead of original product ID
    -- sd.sls_prd_key AS product_key,
    pr.product_key AS product_key,

    -- Use surrogate customer key instead of original customer ID
    -- sd.sls_cust_id AS customer_id,
    cu.customer_key AS customer_key,

    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt AS shipping_date,
    sd.sls_due_dt AS due_date,
    sd.sls_sales AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price AS price

FROM silver.crm_sales_details sd
/* ) t
GROUP BY product_key
HAVING COUNT(*) > 1 */

LEFT JOIN gold.dim_products pr
    ON sd.sls_prd_key = pr.product_number

LEFT JOIN gold.dim_customers cu
    ON sd.sls_cust_id = cu.customer_id;
GO


-- =============================================================================
-- Quality Checks
-- =============================================================================

-- Check the final Gold sales view
--SELECT *FROM gold.fact_sales;


-- =============================================================================
-- Foreign Key Integrity Check: Customer Dimension
-- =============================================================================

-- Check whether every customer_key in fact_sales exists in dim_customers
-- No rows returned = all customer keys are valid
/*SELECT *
FROM gold.fact_sales f

LEFT JOIN gold.dim_customers c
    ON c.customer_key = f.customer_key

WHERE c.customer_key IS NULL;*/


-- =============================================================================
-- Foreign Key Integrity Check: Product Dimension
-- =============================================================================

-- Check whether every product_key in fact_sales exists in dim_products
-- No rows returned = all product keys are valid

/*SELECT *
FROM gold.fact_sales f

LEFT JOIN gold.dim_products p
    ON f.product_key = p.product_key

WHERE p.product_key IS NULL;*/

