SELECT TOP 100 *
FROM bronze.crm_cust_info

SELECT TOP 100 *
FROM bronze.crm_prd_info

SELECT TOP 100 *
FROM bronze.crm_sales_details

SELECT TOP 100 *
FROM bronze.erp_cust_az12

SELECT TOP 100 *
FROM bronze.erp_loc_a101

SELECT TOP 100 *
FROM bronze.erp_px_cat_g1v2


/* ============================================================
    QUALITY CHECK : Check for Nulls or Duplicates in Primary Key 
   ============================================================ */
-- Expectation: No Result 
-- cst_id should be unique and NOT NULL. 

SELECT
cst_id,
COUNT(*) AS Duplicates
FROM bronze.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL

/* ============================================================
   INVESTIGATE DUPLICATES
   ============================================================ */

-- Check one duplicated customer to understand the problem.
-- Example: cst_id 29466 appears multiple times.
SELECT *
FROM bronze.crm_cust_info
WHERE cst_id = 29466;


/* ============================================================
   IDENTIFY THE LATEST CUSTOMER RECORD
   ============================================================ */

-- Give each version of a customer a number.
-- PARTITION BY = restart numbering for each customer.
-- DESC = newest record gets number 1.

SELECT *,
ROW_NUMBER () OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
FROM bronze.crm_cust_info
WHERE cst_id = 29466;


/* ============================================================
   CHECK OLD / DUPLICATE RECORDS
   ============================================================ */

-- flag_last != 1 shows older duplicate records.
SELECT*
FROM (
    SELECT *,
    ROW_NUMBER () OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
    FROM bronze.crm_cust_info
    )t WHERE flag_last !=1


/* ============================================================
   KEEP ONLY THE LATEST RECORD
   ============================================================ */

-- Keep only the newest record for each customer.
-- This removes older duplicates.
SELECT *
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
    FROM bronze.crm_cust_info
) t
WHERE flag_last = 1;


/* ============================================================
   TEST ONE CUSTOMER
   ============================================================ */

-- Only for testing:
-- Check that customer 29466 now has only the latest record.
SELECT *
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
    FROM bronze.crm_cust_info
) t
WHERE flag_last = 1 AND cst_id = 29466  -- it appears now only 1 time (the latest record based on sct_create_date)



-- ==========================================================================================================================

-- QUALITY CHECK: Unwanted Spaces
-- Check string columns for leading or trailing spaces
-- If the original value differs from the trimmed value, unwanted spaces exist
-- Expectation: No Results
-- ==========================================================================================================================

-- Check first name for unwanted spaces
SELECT cst_firstname
FROM bronze.crm_cust_info
WHERE cst_firstname != TRIM(cst_firstname);


-- Check last name for unwanted spaces
SELECT cst_lastname
FROM bronze.crm_cust_info
WHERE cst_lastname != TRIM(cst_lastname);


-- ==========================================================================================================================
-- DATA CLEANING: Remove Unwanted Spaces
-- TRIM() removes leading and trailing spaces from string values
-- ==========================================================================================================================

SELECT
    cst_id, 
    cst_key, 
    TRIM(cst_firstname) AS cst_firstname,
    TRIM(cst_lastname) AS cst_lastname,
    cst_marital_status,
    cst_gndr,
    cst_create_date
FROM bronze.crm_cust_info;


-- ==========================================================================================================================
-- DATA STANDARDIZATION & CONSISTENCY
-- Check low-cardinality columns (columns with only a small number of possible values)
-- Identify all distinct values to detect inconsistent or unclear representations
-- Standardize abbreviated values: F -> Female, M -> Male
-- Same for marital status: S -> Single, M -> Married
-- ==========================================================================================================================

SELECT DISTINCT cst_marital_status
FROM bronze.crm_cust_info;

SELECT DISTINCT cst_gndr
FROM bronze.crm_cust_info;


-- ==========================================================================================================================
-- DATA CLEANING & STANDARDIZATION
-- Clean and standardize customer data before loading it into the Silver Layer
-- ==========================================================================================================================

SELECT
    cst_id, 
    cst_key,

    -- Remove leading and trailing spaces from names
    TRIM(cst_firstname) AS cst_firstname,
    TRIM(cst_lastname) AS cst_lastname,

    -- Standardize marital status:
    -- TRIM removes unwanted spaces
    -- UPPER makes the comparison case-insensitive (e.g. 's', 'S', ' s ' -> 'S')
    -- Replace missing or unexpected values with 'n/a'
    CASE 
        WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
        ELSE 'n/a'
    END AS cst_marital_status,

    -- Standardize gender:
    -- TRIM removes unwanted spaces
    -- UPPER normalizes the value before comparison (e.g. 'f', 'F', ' f ' -> 'F')
    -- Replace missing or unexpected values with 'n/a'
    CASE 
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'n/a'
    END AS cst_gndr,

    cst_create_date

FROM bronze.crm_cust_info;


-- ==========================================================================================================================
-- LOAD CLEANED DATA INTO SILVER LAYER
-- Insert cleaned, standardized and deduplicated customer data
-- ==========================================================================================================================
TRUNCATE TABLE silver.crm_cust_info
INSERT INTO silver.crm_cust_info (
    cst_id,
    cst_key,
    cst_firstname,
    cst_lastname,
    cst_marital_status,
    cst_gndr,
    cst_create_date
)

SELECT
    cst_id,
    cst_key,

    -- Remove leading and trailing spaces
    TRIM(cst_firstname) AS cst_firstname,
    TRIM(cst_lastname) AS cst_lastname,

    -- Standardize marital status
    CASE 
        WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
        ELSE 'n/a'
    END AS cst_marital_status,

    -- Standardize gender
    CASE 
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'n/a'
    END AS cst_gndr,

    cst_create_date

FROM (
    SELECT
        *,
        -- Assign 1 to the newest record for each customer
        -- DESC puts the most recent cst_create_date first
        ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC
        ) AS flag_last
    FROM bronze.crm_cust_info
    -- Ignore records without a customer ID
    WHERE cst_id IS NOT NULL
) t
-- Keep only the newest record for each customer
-- This removes duplicates and keeps the most recent information
WHERE flag_last = 1;




/* ============================================================
   QUALITY CHECKS - SILVER.CRM_CUST_INFO
   Re-run the quality checks after loading the cleaned data
   into the Silver layer to verify data quality.
   ============================================================ */


/* ============================================================
   Check for NULLs or Duplicates in Primary Key
   Expectation: No Results
   cst_id should be unique and NOT NULL.
   ============================================================ */

SELECT
    cst_id,
    COUNT(*) AS Duplicates
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;


/* ============================================================
   Check for Unwanted Spaces
   Expectation: No Results
   First and last names should not contain leading or trailing spaces.
   ============================================================ */

-- Check first name for unwanted spaces
SELECT cst_firstname
FROM silver.crm_cust_info
WHERE cst_firstname != TRIM(cst_firstname);


-- Check last name for unwanted spaces
SELECT cst_lastname
FROM silver.crm_cust_info
WHERE cst_lastname != TRIM(cst_lastname);


/* ============================================================
   Check Data Standardization & Consistency
   Verify that coded values were transformed into
   clear and standardized values.
   
   Expected:
   Marital Status -> Single, Married, n/a
   Gender         -> Male, Female, n/a
   ============================================================ */

-- Check all distinct marital status values
SELECT DISTINCT cst_marital_status
FROM silver.crm_cust_info;


-- Check all distinct gender values
SELECT DISTINCT cst_gndr
FROM silver.crm_cust_info;


/* ============================================================
   Final Check
   Display the cleaned data from the Silver table.
   ============================================================ */

SELECT *
FROM silver.crm_cust_info;






/* ============================================================
   DATA QUALITY CHECKS & TRANSFORMATIONS: crm_prd_info
   ============================================================ */

-- View all product data
SELECT *
FROM bronze.crm_prd_info;


-- Check for NULLs or duplicates in the Primary Key
-- Expectation: No results -> prd_id should be unique and NOT NULL
SELECT 
    prd_id, 
    COUNT(*) AS Duplicates
FROM bronze.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL; 


-- Transform product key:
-- Example: CO-RF-FR-R92B-58
-- caty ID: CO-RF -> CO_RF
-- Product Key: FR-R92B-58
SELECT 
    prd_id,
    prd_key,
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,     -- SUBSTRING(prd_key, 1, 5): starts at position 1 and takes 5 characters (CO-RF)
                                                                    -- REPLACE: replaces "-" with "_" to match the ERP cat ID format (CO_RF)
    SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
    prd_nm,
    prd_cost,
    prd_line,
    prd_start_dt,
    prd_end_dt
FROM bronze.crm_prd_info;


-- Check if transformed cat IDs exist in the ERP cat table
-- Returns only cat IDs that have NO matching record in ERP
SELECT 
    prd_id,
    prd_key,
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id
FROM bronze.crm_prd_info
WHERE REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') NOT IN (
    SELECT DISTINCT id FROM bronze.erp_px_cat_g1v2
);


-- Check if transformed Product Keys exist in the Sales table
-- Returns only Product Keys that have NO matching sales record
SELECT 
    prd_id,
    prd_key,
    SUBSTRING(prd_key, 7, LEN(prd_key)) AS transformed_prd_key
FROM bronze.crm_prd_info
WHERE SUBSTRING(prd_key, 7, LEN(prd_key)) NOT IN (
    SELECT sls_prd_key FROM bronze.crm_sales_details
);

-- Reference values from ERP
-- ERP uses "_" while CRM uses "-", therefore REPLACE is needed
SELECT DISTINCT id
FROM bronze.erp_px_cat_g1v2;

-- Reference Product Keys from Sales
SELECT DISTINCT sls_prd_key
FROM bronze.crm_sales_details;


-- ============================================================
-- DATA QUALITY CHECKS - BRONZE LAYER
-- ============================================================

-- Check for unwanted spaces in product names
-- Expectation: No Results
SELECT prd_nm
FROM bronze.crm_prd_info
WHERE prd_nm != TRIM(prd_nm);


-- Check for NULL or negative product costs
-- Expectation: No Results
SELECT prd_cost
FROM bronze.crm_prd_info
WHERE prd_cost IS NULL OR prd_cost < 0;


-- ============================================================
-- DATA TRANSFORMATION PREVIEW
-- ============================================================

SELECT 
    prd_id,
    prd_key,

    -- Extract category ID from the first 5 characters
    -- and replace '-' with '_' to match the category table format
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,

    -- Extract the product key starting from character 7
    SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,

    prd_nm,

    -- Replace NULL product costs with 0
    ISNULL(prd_cost, 0) AS prd_cost,

    -- Standardize product line codes into descriptive values
    CASE UPPER(TRIM(prd_line))
        WHEN 'M' THEN 'Mountain'
        WHEN 'R' THEN 'Road'
        WHEN 'S' THEN 'Other Sales'
        WHEN 'T' THEN 'Touring'
        ELSE 'n/a'
    END AS prd_line,

    prd_start_dt,
    prd_end_dt

FROM bronze.crm_prd_info;


-- Check all existing product line values before standardization
SELECT DISTINCT prd_line
FROM bronze.crm_prd_info;


-- ============================================================
-- DATE QUALITY CHECKS
-- ============================================================

-- Check for invalid date order
-- End date must not be earlier than start date
-- Expectation: No Results
SELECT *
FROM bronze.crm_prd_info
WHERE prd_end_dt < prd_start_dt;


-- Date quality issues to check:
-- 1. End date must not be earlier than the start date
-- 2. Date ranges for the same product must not overlap
-- 3. Every record must have a start date
-- 4. The last/current record can have a NULL end date


-- Test deriving the end date from the next record
SELECT
    prd_id,
    prd_key,
    prd_nm,
    prd_start_dt,
    prd_end_dt,

    -- LEAD accesses the next row within the same product
    -- New end date = next record's start date - 1 day
    -- The last record gets NULL because there is no next record
    LEAD(prd_start_dt) OVER (
        PARTITION BY prd_key 
        ORDER BY prd_start_dt
    ) - 1 AS prd_end_dt_test

FROM bronze.crm_prd_info

-- Filter specific products only for testing the date logic
WHERE prd_key IN ('AC-HE-HL-U509-R', 'AC-HE-HL-U509');


-- ============================================================
-- LOAD CLEANED DATA INTO SILVER LAYER
-- ============================================================
TRUNCATE TABLE silver.crm_prd_info
INSERT INTO silver.crm_prd_info (
    prd_id,
    cat_id,
    prd_key,
    prd_nm,
    prd_cost,
    prd_line,
    prd_start_dt,
    prd_end_dt
)
SELECT 
    prd_id,

    -- Derive category ID and standardize its format
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,

    -- Extract product-specific part of the key
    SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,

    prd_nm,

    -- Replace missing costs with 0
    ISNULL(prd_cost, 0) AS prd_cost,

    -- Map product line codes to descriptive values
    CASE UPPER(TRIM(prd_line))
        WHEN 'M' THEN 'Mountain'
        WHEN 'R' THEN 'Road'
        WHEN 'S' THEN 'Other Sales'
        WHEN 'T' THEN 'Touring'
        ELSE 'n/a'
    END AS prd_line,

    -- Convert DATETIME to DATE because the time component is not needed
    CAST(prd_start_dt AS DATE) AS prd_start_dt,

    -- Access the next row and use its start date - 1 day as the current end date
    -- PARTITION BY ensures the calculation is done separately for each product
    -- The current/latest product record remains NULL because no next record exists
    CAST(
        LEAD(prd_start_dt) OVER (
            PARTITION BY prd_key 
            ORDER BY prd_start_dt
        ) - 1 AS DATE
    ) AS prd_end_dt

FROM bronze.crm_prd_info;


-- ============================================================
-- DATA QUALITY CHECKS - SILVER LAYER
-- ============================================================

-- Check for NULL or negative product costs after transformation
-- Expectation: No Results
SELECT prd_cost
FROM silver.crm_prd_info
WHERE prd_cost IS NULL OR prd_cost < 0;


-- Check standardized product line values
-- Expectation: Mountain, Road, Other Sales, Touring, n/a
SELECT DISTINCT prd_line
FROM silver.crm_prd_info;


-- Check for invalid date order after transformation
-- End date must not be earlier than start date
-- Expectation: No Results
SELECT *
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;


-- Final check of cleaned Silver table
SELECT *
FROM silver.crm_prd_info;


--===========================================================================================

-- Check if all product keys in sales exist in the product table
-- Expectation: No Results
SELECT *
FROM bronze.crm_sales_details
WHERE sls_prd_key NOT IN (SELECT prd_key FROM silver.crm_prd_info);

-- Check if all customers ids in sales exist in the customer table
-- Expectation: No Results
SELECT *
FROM bronze.crm_sales_details
WHERE sls_cust_id NOT IN (SELECT cst_id FROM silver.crm_cust_info);

-- Check for invalid dates
-- Expectation: No invalid values outside the accepted range
SELECT 
    NULLIF(sls_order_dt, 0) AS sls_order_dt
FROM bronze.crm_sales_details
WHERE sls_order_dt <= 0 
   OR LEN(sls_order_dt) != 8
   OR sls_order_dt > 20160101 
   OR sls_order_dt < 19500101;


-- Check shipping dates for invalid values
SELECT 
    NULLIF(sls_ship_dt, 0) AS sls_ship_dt
FROM bronze.crm_sales_details
WHERE sls_ship_dt <= 0 
   OR LEN(sls_ship_dt) != 8
   OR sls_ship_dt > 20160101 
   OR sls_ship_dt < 19500101;


-- Check due dates for invalid values
SELECT 
    NULLIF(sls_due_dt, 0) AS sls_due_dt
FROM bronze.crm_sales_details
WHERE sls_due_dt <= 0 
   OR LEN(sls_due_dt) != 8
   OR sls_due_dt > 20500101 
   OR sls_due_dt < 19500101;


-- Check for invalid date order
-- Order date must be earlier than or equal to shipping and due date
-- Expectation: No Results
SELECT *
FROM bronze.crm_sales_details
WHERE sls_order_dt > sls_ship_dt 
   OR sls_order_dt > sls_due_dt;


-- Check consistency between sales, quantity and price
-- Business rule: Sales = Quantity * Price
-- NULL, zero and negative values are not allowed
SELECT DISTINCT 
    sls_sales,
    sls_quantity,
    sls_price
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
   OR sls_sales IS NULL 
   OR sls_quantity IS NULL 
   OR sls_price IS NULL
   OR sls_sales <= 0 
   OR sls_quantity <= 0 
   OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price;


-- Preview transformations before loading into the Silver layer
SELECT DISTINCT 
    sls_sales AS old_sls_sales,
    sls_quantity,
    sls_price AS old_sls_price,

    -- Recalculate sales if missing, invalid or inconsistent
    -- ABS() converts a negative price to a positive value
    CASE 
        WHEN sls_sales IS NULL 
          OR sls_sales <= 0 
          OR sls_sales != sls_quantity * ABS(sls_price)
        THEN sls_quantity * ABS(sls_price)
        ELSE sls_sales
    END AS sls_sales,

    -- Recalculate price if missing, zero or negative
    -- NULLIF prevents division by zero
    CASE 
        WHEN sls_price IS NULL 
          OR sls_price <= 0
        THEN sls_sales / NULLIF(sls_quantity, 0)
        ELSE sls_price
    END AS sls_price

FROM bronze.crm_sales_details;


-- Load cleaned and transformed data into the Silver layer
TRUNCATE TABLE  silver.crm_sales_details
INSERT INTO silver.crm_sales_details (
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt,
    sls_sales,
    sls_quantity,
    sls_price
)

SELECT 
    sls_ord_num, 
    sls_prd_key, 
    sls_cust_id,

    -- Convert YYYYMMDD integer to DATE, first must convert in VARCHAR, then in DATE 
    -- Invalid values (0 or wrong length) are replaced with NULL
    CASE 
        WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE) 
    END AS sls_order_dt,

    CASE 
        WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE) 
    END AS sls_ship_dt,

    CASE 
        WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
        ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE) 
    END AS sls_due_dt,

    -- Recalculate sales if missing, invalid or inconsistent
    CASE 
        WHEN sls_sales IS NULL 
          OR sls_sales <= 0 
          OR sls_sales != sls_quantity * ABS(sls_price)
        THEN sls_quantity * ABS(sls_price)
        ELSE sls_sales
    END AS sls_sales,

    sls_quantity,

    -- Recalculate price if missing or invalid
    -- NULLIF(quantity, 0) prevents division by zero
    CASE 
        WHEN sls_price IS NULL OR sls_price <= 0
        THEN sls_sales / NULLIF(sls_quantity, 0)
        ELSE sls_price
    END AS sls_price

FROM bronze.crm_sales_details;


-- Quality check after loading into the Silver layer
-- Business rule: Sales = Quantity * Price
-- Expectation: No Results
SELECT DISTINCT 
    sls_sales,
    sls_quantity,
    sls_price
FROM silver.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
   OR sls_sales IS NULL 
   OR sls_quantity IS NULL 
   OR sls_price IS NULL
   OR sls_sales <= 0 
   OR sls_quantity <= 0 
   OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price;


SELECT*FROM silver.crm_sales_details


--====================================================================
-- Check if all customer IDs from ERP exist in the CRM customer table
-- Remove the 'NAS' prefix before comparison
-- Expectation: No Results

SELECT cid,
CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
ELSE cid 
END cid,
bdate,
gen
FROM bronze.erp_cust_az12
--WHERE cid LIKE '%AW00011000'
WHERE CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
ELSE cid 
END NOT IN (SELECT DISTINCT cst_key FROM silver.crm_cust_info)


SELECT*FROM bronze.crm_cust_info


--Identify Out-of-Range Dates
SELECT bdate 
FROM bronze.erp_cust_az12
WHERE bdate < '1926-01-01' OR bdate > GETDATE()


-- Data Standardization and Consistency
SELECT DISTINCT
    gen,
    CASE 
    WHEN UPPER(TRIM(REPLACE(gen, CHAR(13), ''))) IN ('M', 'MALE') 
        THEN 'Male'
    WHEN UPPER(TRIM(REPLACE(gen, CHAR(13), ''))) IN ('F', 'FEMALE') 
        THEN 'Female'
    ELSE 'n/a'
END AS gen
FROM bronze.erp_cust_az12;


TRUNCATE TABLE silver.erp_cust_az12
INSERT INTO silver.erp_cust_az12 (cid,bdate,gen)
SELECT
CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
ELSE cid 
END cid,

CASE WHEN bdate < '1926-01-01' OR bdate > GETDATE() THEN NULL 
    ELSE bdate
    END bdate,

 CASE WHEN UPPER(TRIM(REPLACE(gen, CHAR(13), ''))) IN ('M', 'MALE') THEN 'Male'
    WHEN UPPER(TRIM(REPLACE(gen, CHAR(13), ''))) IN ('F', 'FEMALE')  THEN 'Female'
    ELSE 'n/a'
END gen
FROM bronze.erp_cust_az12


-- Quality Check 
--Identify Out-of-Range Dates
SELECT bdate 
FROM silver.erp_cust_az12
WHERE bdate < '1926-01-01' OR bdate > GETDATE()


-- Data Standardization and Consistency
SELECT DISTINCT
   gen
FROM silver.erp_cust_az12;

SELECT*FROM silver.erp_cust_az12;





/* ============================================================
   ERP LOCATION - DATA CLEANING
   ============================================================ */


-- Preview cleaned customer ID
-- Remove '-' from cid to match the customer key format
SELECT 
    REPLACE(cid, '-', '') AS cid,
    cntry
FROM bronze.erp_loc_a101;


-- Check customer keys from CRM
-- Used to compare with cleaned ERP customer IDs
SELECT cst_key
FROM bronze.crm_cust_info;


/* ============================================================
   DATA STANDARDIZATION AND CONSISTENCY
   ============================================================ */


-- Check distinct country values before transformation
SELECT DISTINCT cntry
FROM bronze.erp_loc_a101
ORDER BY cntry;


-- Standardize country values
-- CHAR(13) = carriage return (\r) left from CSV line endings during BULK INSERT
-- Remove it to ensure correct comparison and avoid hidden characters
SELECT
    CASE 
        WHEN TRIM(REPLACE(cntry, CHAR(13), '')) = 'DE' 
            THEN 'Germany'

        WHEN TRIM(REPLACE(cntry, CHAR(13), '')) IN ('US', 'USA') 
            THEN 'United States'

        WHEN TRIM(REPLACE(cntry, CHAR(13), '')) = '' 
             OR cntry IS NULL 
            THEN 'n/a'

        ELSE TRIM(REPLACE(cntry, CHAR(13), ''))
    END AS cntry
FROM bronze.erp_loc_a101;


/* ============================================================
   LOAD CLEANED DATA INTO SILVER
   ============================================================ */
TRUNCATE TABLE silver.erp_loc_a101
INSERT INTO silver.erp_loc_a101 (
    cid,
    cntry
)

SELECT
    -- Remove '-' from customer ID
    REPLACE(cid, '-', '') AS cid,

    -- Standardize country values and handle missing values
    -- CHAR(13) removes the hidden carriage return left from the CSV line ending
    CASE 
        WHEN TRIM(REPLACE(cntry, CHAR(13), '')) = 'DE' 
            THEN 'Germany'

        WHEN TRIM(REPLACE(cntry, CHAR(13), '')) IN ('US', 'USA') 
            THEN 'United States'

        WHEN TRIM(REPLACE(cntry, CHAR(13), '')) = '' 
             OR cntry IS NULL 
            THEN 'n/a'

        ELSE TRIM(REPLACE(cntry, CHAR(13), ''))
    END AS cntry

FROM bronze.erp_loc_a101;


/* ============================================================
   QUALITY CHECK
   ============================================================ */


-- Check standardized country values
SELECT DISTINCT cntry
FROM silver.erp_loc_a101
ORDER BY cntry;


-- Check loaded Silver data
SELECT *
FROM silver.erp_loc_a101;


-- ============================================================
-- ERP PRODUCT CATEGORY
-- Source: Bronze Layer
-- Target: Silver Layer
-- ============================================================


-- ============================================================
-- DATA EXPLORATION
-- ============================================================

-- Preview source data
SELECT
    id,
    cat,
    subcat,
    maintenance
FROM bronze.erp_px_cat_g1v2;


-- Check CRM product data for related category IDs
SELECT *
FROM bronze.crm_prd_info;


-- ============================================================
-- DATA QUALITY CHECK
-- ============================================================

-- Check for unwanted leading or trailing spaces
SELECT *
FROM bronze.erp_px_cat_g1v2
WHERE cat != TRIM(cat)
   OR subcat != TRIM(subcat)
   OR maintenance != TRIM(maintenance);


-- ============================================================
-- DATA STANDARDIZATION AND CONSISTENCY
-- ============================================================

-- Check unique category values
SELECT DISTINCT cat
FROM bronze.erp_px_cat_g1v2;

-- Check unique subcategory values
SELECT DISTINCT subcat
FROM bronze.erp_px_cat_g1v2;

-- Check unique maintenance values
SELECT DISTINCT maintenance
FROM bronze.erp_px_cat_g1v2;


-- ============================================================
-- LOAD CLEANED DATA INTO SILVER LAYER
-- ============================================================

TRUNCATE TABLE silver.erp_px_cat_g1v2
INSERT INTO silver.erp_px_cat_g1v2
(
    id,
    cat,
    subcat,
    maintenance
)
SELECT
    id,
    cat,
    subcat,

    -- CHAR(13) is a hidden carriage-return character from the CSV import.
    -- Remove it and trim remaining spaces.
    TRIM(REPLACE(maintenance, CHAR(13), '')) AS maintenance

FROM bronze.erp_px_cat_g1v2;


-- ============================================================
-- QUALITY CHECK - SILVER TABLE
-- ============================================================

-- Verify the cleaned data loaded into Silver
SELECT *
FROM silver.erp_px_cat_g1v2;

