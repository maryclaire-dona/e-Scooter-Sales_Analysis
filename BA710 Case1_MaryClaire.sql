
/***BE SURE TO DROP ALL TABLES IN WORK THAT BEGIN WITH "CASE_"***/

/*Set Time Zone*/
set time_zone='-4:00';
select now();

/***PRELIMINARY ANALYSIS***/

/*Create a VIEW in WORK called CASE_SCOOT_NAMES that is a subset of the prod table
which only contains scooters.
Result should have 7 records.*/

CREATE OR REPLACE VIEW work.case_scoot_names AS
  SELECT *
  FROM ba710case.ba710_prod
  WHERE product_type = 'scooter';

SELECT * FROM work.case_scoot_names;

/*The following code uses a join to combine the view above with the sales information.
  Can the expected performance be improved using an index?
  A) Calculate the EXPLAIN COST.
  B) Create the appropriate indexes.
  C) Calculate the new EXPLAIN COST.
  D) What is your conclusion?:
*/

select a.model, a.product_type, a.product_id,
    b.customer_id, b.sales_transaction_date, date(b.sales_transaction_date) as sale_date,
    b.sales_amount, b.channel, b.dealership_id
from work.case_scoot_names a 
inner join ba710case.ba710_sales b
    on a.product_id=b.product_id;
 
 
/* A) Calculate the EXPLAIN COST */

EXPLAIN FORMAT=json SELECT a.model, a.product_type, a.product_id,
    b.customer_id, b.sales_transaction_date, DATE(b.sales_transaction_date) AS sale_date,
    b.sales_amount, b.channel, b.dealership_id
FROM work.case_scoot_names a 
INNER JOIN ba710case.ba710_sales b
    ON a.product_id=b.product_id;

/***
{
  "query_block": {
    "select_id": 1,
    "cost_info": {
      "query_cost": "4597.05"
    },
    "nested_loop": [
      {
        "table": {
          "table_name": "ba710_prod",
          "access_type": "ALL",
          "rows_examined_per_scan": 12,
          "rows_produced_per_join": 1,
          "filtered": "10.00",
          "cost_info": {
            "read_cost": "1.33",
            "eval_cost": "0.12",
            "prefix_cost": "1.45",
            "data_read_per_join": "67"
          },
          "used_columns": [
            "product_id",
            "model",
            "product_type"
          ],
          "attached_condition": "(`ba710case`.`ba710_prod`.`product_type` = 'scooter')"
        }
      },
      {
        "table": {
          "table_name": "b",
          "access_type": "ALL",
          "rows_examined_per_scan": 37825,
          "rows_produced_per_join": 4539,
          "filtered": "10.00",
          "using_join_buffer": "hash join",
          "cost_info": {
            "read_cost": "56.60",
            "eval_cost": "453.90",
            "prefix_cost": "4597.05",
            "data_read_per_join": "212K"
          },
          "used_columns": [
            "customer_id",
            "product_id",
            "sales_transaction_date",
            "sales_amount",
            "channel",
            "dealership_id"
          ],
          "attached_condition": "(`ba710case`.`b`.`product_id` = `ba710case`.`ba710_prod`.`product_id`)"
        }
      }
    ]
  }
}

***/

/* B.) Create the appropriate indexes */

CREATE INDEX idx_productid ON ba710case.ba710_sales (product_id);
CREATE INDEX idx_productidw ON ba710case.ba710_prod (product_id);

/** C.) Calculate the new EXPLAIN COST */

EXPLAIN FORMAT=json SELECT a.model, a.product_type, a.product_id,
    b.customer_id, b.sales_transaction_date, DATE(b.sales_transaction_date) AS sale_date,
    b.sales_amount, b.channel, b.dealership_id
FROM work.case_scoot_names a 
INNER JOIN ba710case.ba710_sales b
    ON a.product_id=b.product_id;

/**
{
  "query_block": {
    "select_id": 1,
    "cost_info": {
      "query_cost": "616.59"
    },
    "nested_loop": [
      {
        "table": {
          "table_name": "ba710_prod",
          "access_type": "ALL",
          "possible_keys": [
            "idx_productidw"
          ],
          "rows_examined_per_scan": 12,
          "rows_produced_per_join": 1,
          "filtered": "10.00",
          "cost_info": {
            "read_cost": "1.33",
            "eval_cost": "0.12",
            "prefix_cost": "1.45",
            "data_read_per_join": "67"
          },
          "used_columns": [
            "product_id",
            "model",
            "product_type"
          ],
          "attached_condition": "((`ba710case`.`ba710_prod`.`product_type` = 'scooter') and (`ba710case`.`ba710_prod`.`product_id` is not null))"
        }
      },
      {
        "table": {
          "table_name": "b",
          "access_type": "ref",
          "possible_keys": [
            "idx_productid"
          ],
          "key": "idx_productid",
          "used_key_parts": [
            "product_id"
          ],
          "key_length": "9",
          "ref": [
            "ba710case.ba710_prod.product_id"
          ],
          "rows_examined_per_scan": 3438,
          "rows_produced_per_join": 4126,
          "filtered": "100.00",
          "cost_info": {
            "read_cost": "202.50",
            "eval_cost": "412.64",
            "prefix_cost": "616.59",
            "data_read_per_join": "193K"
          },
          "used_columns": [
            "customer_id",
            "product_id",
            "sales_transaction_date",
            "sales_amount",
            "channel",
            "dealership_id"
          ]
        }
      }
    ]
  }
}

**/

/** D.) What is your conclusion?:
Creating indexes for product_id field in sales and prod table decreases 
the overall query cost from 4597.05 down to 616.59 **/

    
/***PART 1: INVESTIGATE BAT SALES TRENDS***/  
    
/*The following creates a table of daily sales with four columns and will be used in the following step.*/

CREATE TABLE work.case_daily_sales AS
	select p.model, p.product_id, date(s.sales_transaction_date) as sale_date, 
		   round(sum(s.sales_amount),2) as daily_sales
	from ba710case.ba710_sales as s 
    inner join ba710case.ba710_prod as p
		on s.product_id=p.product_id
    group by date(s.sales_transaction_date),p.product_id,p.model;

select * from work.case_daily_sales;


/*Create a view (5 columns)of cumulative sales figures for just the Bat scooter from
the daily sales table you created.
Using the table created above, add a column that contains the cumulative
sales amount (one row per date).
Hint: Window Functions, Over*/

CREATE OR REPLACE VIEW work.case_batscooter_cum AS
 SELECT *,
  ROUND((SUM(daily_sales) OVER(ROWS UNBOUNDED PRECEDING)),2) AS cumulative_sales
 FROM work.case_daily_sales
 WHERE model='Bat'
 ORDER BY sale_date;

SELECT * FROM work.case_batscooter_cum;

/*Using the view above, create a VIEW (6 columns) that computes the cumulative sales 
for the previous 7 days for just the Bat scooter. 
(i.e., running total of sales for 7 rows inclusive of the current row.)
This is calculated as the 7 day lag of cumulative sum of sales
(i.e., each record should contain the sum of sales for the current date plus
the sales for the preceeding 6 records).
*/

CREATE VIEW work.case_batscooter_7days_cum AS
 SELECT *,
  ROUND((SUM(daily_sales) OVER(ROWS BETWEEN 6 PRECEDING and CURRENT ROW)),2) AS cumu_sales_7_days
 FROM work.case_batscooter_cum
 ORDER BY sale_date;

SELECT * FROM work.case_batscooter_7days_cum;



/*Using the view you just created, create a new view (7 columns) that calculates
the weekly sales growth as a percentage change of cumulative sales
compared to the cumulative sales from the previous week (seven days ago).

See the Word document for an example of the expected output for the Blade scooter.*/

CREATE VIEW work.case_batpct_weekly_growth AS
SELECT *,
	ROUND(((cumulative_sales-LAG(cumulative_sales,7) OVER())/LAG(cumulative_sales,7) OVER())*100,2) 
	AS pct_weekly_increase_cumu_sales
FROM work.case_batscooter_7days_cum
ORDER BY sale_date;

SELECT * FROM work.case_batpct_weekly_growth;

/*Paste a screenshot of at least the first 10 records of the table
  and answer the questions in the Word document*/
  
SELECT * FROM work.case_batpct_weekly_growth;  

/* Question 1 - What date does the cumulative weekly sales growth drop below 10%?*/

SELECT * 
FROM work.case_batpct_weekly_growth
WHERE pct_weekly_increase_cumu_sales <10
LIMIT 1;  

/* Question 2 - How many days since the launch date did it take for cumulative sales growth
to drop below 10%? */

SELECT DATEDIFF((SELECT sale_date FROM work.case_batpct_weekly_growth
WHERE pct_weekly_increase_cumu_sales <10
LIMIT 1),(SELECT sale_date FROM work.case_batpct_weekly_growth
LIMIT 1)) AS num_days_before_growth_below10pct;


/*********************************************************************************************
Is the launch timing (October) a potential cause for the drop?
Replicate the Bat sales cumulative analysis for the Bat Limited Edition.
*/

CREATE OR REPLACE VIEW work.case_batlimedscooter_cum AS
 SELECT *,
  ROUND((SUM(daily_sales) OVER(ROWS UNBOUNDED PRECEDING)),2) AS cumulative_sales
 FROM work.case_daily_sales
 WHERE model='Bat Limited Edition'
 ORDER BY sale_date;

SELECT * FROM work.case_batlimedscooter_cum;


CREATE VIEW work.case_batlimedscooter_7days_cum AS
 SELECT *,
  ROUND((SUM(daily_sales) OVER(ROWS BETWEEN 6 PRECEDING and CURRENT ROW)),2) AS cumu_sales_7_days
 FROM work.case_batlimedscooter_cum
 ORDER BY sale_date;

SELECT * FROM work.case_batlimedscooter_7days_cum;


CREATE VIEW work.case_batlimedpct_weekly_growth AS
SELECT *,
	ROUND(((cumulative_sales-LAG(cumulative_sales,7) OVER())/LAG(cumulative_sales,7) OVER())*100,2) 
	AS pct_weekly_increase_cumu_sales
FROM work.case_batlimedscooter_7days_cum
ORDER BY sale_date;

SELECT * FROM work.case_batlimedpct_weekly_growth;


/*Paste a screenshot of at least the first 10 records of the table
  and answer the questions in the Word document*/
  
SELECT * FROM work.case_batlimedpct_weekly_growth;  
  
/* Question 1 - What date does the cumulative weekly sales growth drop below 10%?*/

SELECT * 
FROM work.case_batlimedpct_weekly_growth
WHERE pct_weekly_increase_cumu_sales <10
LIMIT 1;  

/* Question 2 - How many days since the launch date did it take for cumulative sales growth
to drop below 10%? */

SELECT DATEDIFF((SELECT sale_date FROM work.case_batlimedpct_weekly_growth
WHERE pct_weekly_increase_cumu_sales <10
LIMIT 1),(SELECT sale_date FROM work.case_batlimedpct_weekly_growth
LIMIT 1)) AS num_days_before_growth_below10pct;
  


/*********************************************************************************************
However, the Bat Limited was at a higher price point.
Let's take a look at the 2013 Lemon model, since it's a similar price point.  
Is the launch timing (October) a potential cause for the drop?
Replicate the Bat sales cumulative analysis for the 2013 Lemon model.*/

CREATE OR REPLACE VIEW work.case_lemonscooter_cum AS
 SELECT *,
  ROUND((SUM(daily_sales) OVER(ROWS UNBOUNDED PRECEDING)),2) AS cumulative_sales
 FROM work.case_daily_sales
 WHERE model='Lemon' and YEAR(sale_date)>=2013 
 ORDER BY sale_date;

SELECT * FROM work.case_lemonscooter_cum;


CREATE VIEW work.case_lemonscooter_7days_cum AS
 SELECT *,
  ROUND((SUM(daily_sales) OVER(ROWS BETWEEN 6 PRECEDING and CURRENT ROW)),2) AS cumu_sales_7_days
 FROM work.case_lemonscooter_cum
 ORDER BY sale_date;

SELECT * FROM work.case_lemonscooter_7days_cum;


CREATE VIEW work.case_lemonpct_weekly_growth AS
SELECT *,
	ROUND(((cumulative_sales-LAG(cumulative_sales,7) OVER())/LAG(cumulative_sales,7) OVER())*100,2) 
	AS pct_weekly_increase_cumu_sales
FROM work.case_lemonscooter_7days_cum
ORDER BY sale_date;

SELECT * FROM work.case_lemonpct_weekly_growth;

/*Paste a screenshot of at least the first 10 records of the table
  and answer the questions in the Word document*/

SELECT * FROM work.case_lemonpct_weekly_growth;

/* Question 1 - What date does the cumulative weekly sales growth drop below 10%?*/

SELECT * 
FROM work.case_lemonpct_weekly_growth
WHERE pct_weekly_increase_cumu_sales <10
LIMIT 1;  

/* Question 2 - How many days since the launch date did it take for cumulative sales growth
to drop below 10%? */

SELECT DATEDIFF((SELECT sale_date FROM work.case_lemonpct_weekly_growth
WHERE pct_weekly_increase_cumu_sales <10
LIMIT 1),(SELECT sale_date FROM work.case_lemonpct_weekly_growth
LIMIT 1)) AS num_days_before_growth_below10pct;
