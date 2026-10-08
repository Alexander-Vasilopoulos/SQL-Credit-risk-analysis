-- 0. Database and raw table
CREATE DATABASE IF NOT EXISTS credit_risk_dataset;
USE credit_risk_dataset;


DROP TABLE IF EXISTS credit_risk;
CREATE TABLE IF NOT EXISTS credit_risk (
	credit_id                  INT AUTO_INCREMENT PRIMARY KEY, -- added a primary key
    person_age                 INT,
    person_income              INT,
    person_home_ownership      VARCHAR(20),
    person_emp_length          DOUBLE,
    loan_intent                VARCHAR(30),
    loan_grade                 CHAR(1),
    loan_amnt                  INT,
    loan_int_rate              DOUBLE,
    loan_status                TINYINT,
    loan_percent_income        DOUBLE,
    cb_person_default_on_file  CHAR(1),
    cb_person_cred_hist_length INT
);


-- SET GLOBAL local_infile = 1; use if you get an error code: 3948 to enable loading local data

LOAD DATA LOCAL INFILE '/path/to/credit_risk_dataset.csv'  -- adjust to your local path
INTO TABLE credit_risk
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(person_age, person_income, person_home_ownership, @emp_length, loan_intent,
 loan_grade, loan_amnt, @int_rate, loan_status, loan_percent_income,
 cb_person_default_on_file, cb_person_cred_hist_length)
SET person_emp_length = NULLIF(@emp_length, ''),
    loan_int_rate     = NULLIF(@int_rate, '');

SELECT * FROM credit_risk
LIMIT 100;

SELECT COUNT(*) FROM credit_risk;  -- expect 32581



####### OUTLINE
/*
0. Setup                                            
1. Data Exploration and Preparation for Task 1      
	1.1 Exploration and Outliers                    
	1.2 Duplicate Removal                           
    
2. Data Analysis - TASK 1                           
	2.1 loan_status/loan_grades                     
    2.2 loan_status/loan_amount                     
    2.3 loan status/loan amount grouping            
    2.4 loan_status/loan_percent_income grouping    
    2.5 loan_status/person home ownership           
    2.6 loan_status/loans_by_prior_defaults         
3. Misclassified Loans - Task 1                     
4. Task 1 Summary & Key Insights                    

5. TASK 2                                           
5.1 risk_categories_all                             
5.2 risk_categories_distribution                    

6. Additional Task (Scoring)                        
6.1 scored_all                                      
6.2 scored_distribution                             

INFO: Overviews from sections 2, 5, and 6 are created as database views.
*/


#########  SETUP ############


-- Create new table for manipulation
DROP TABLE IF EXISTS credit_risk2;

CREATE TABLE IF NOT EXISTS credit_risk2
LIKE credit_risk;

INSERT INTO credit_risk2
SELECT *
FROM credit_risk;


-- Rename column for aesthetic preference
ALTER TABLE credit_risk2
RENAME COLUMN loan_amnt TO loan_amount;



###############  Exploration and Preparation Task 1 #####################

-- NULL values in person_emp_length and loan_int_rate --> ?
SELECT COUNT(*)
FROM credit_risk2
WHERE person_emp_length IS NULL; -- --> 887 significant --> ? needs fixing


SELECT COUNT(*)
FROM credit_risk2
WHERE loan_int_rate IS NULL;  -- --> 3,095 almost 10% -- > significant, needs separate investigation and verification/imputation later

WITH cte AS (
SELECT CASE WHEN loan_int_rate IS NULL THEN "Is Null" ELSE "Has Values" END AS loan_int_rate_status,
SUM(CASE WHEN loan_status=1 
	THEN 1
	ELSE 0
	END) AS defaults,
SUM(CASE WHEN loan_status=0 
	THEN 1
	ELSE 0
	END) AS not_defaulted,
COUNT(*) AS total_credit_count
FROM credit_risk2
GROUP BY loan_int_rate_status
)
SELECT loan_int_rate_status, defaults, not_defaulted, total_credit_count, ROUND(defaults/total_credit_count*100,2) AS default_rate_in_percent
FROM cte; -- -- > Distribution of loan_int_rate and defaults is almost identical -- > clean data in future -- > ignore for current analysis

-- Individuals over 100 years old --> clear age/set to null
SELECT *
FROM credit_risk
ORDER BY person_age DESC
LIMIT 6; 

-- max age
SELECT MAX(person_age)
FROM credit_risk; -- max age implausible at 144

UPDATE credit_risk2
SET person_age=NULL
WHERE person_age > 100; 

-- Average age check
SELECT avg(person_age)
FROM credit_risk2; -- Average age is around 27.7

SELECT COUNT(*)
FROM credit_risk2
WHERE person_age IS NULL; -- --> now 5 records

 
-- person_emp_length over 100  --> query clients
SELECT *
FROM credit_risk2
WHERE person_emp_length > 100
ORDER BY person_emp_length DESC; -- > query clients --> values cleared in next step

UPDATE credit_risk2
SET person_emp_length=NULL
WHERE person_emp_length > 100; -- --> clear all values for individuals with over 100 years of work experience

SELECT *
FROM credit_risk2
ORDER BY person_emp_length DESC
LIMIT 100;

-- Unrealistic emp_length compared to age at employment start
SELECT credit_id, person_age, person_emp_length, person_age-person_emp_length AS starting_age, COUNT(*) OVER() AS total_under_starting_age_of_18
FROM credit_risk2
HAVING starting_age BETWEEN 15 AND 18; -- --> 9,228 individuals hired as minors --> check validity

-- Income outlier check
SELECT *
FROM credit_risk2
ORDER BY person_income DESC
LIMIT 100;  -- > one credit has over 6,000,000 --> check validity

SELECT COUNT(*) FROM credit_risk2 WHERE person_income > 1000000; -- 9 credits over a 1 million -- > check validity

-- Check for spelling errors and unnecessary whitespaces in loan_intent and person_home_ownership --> all ok
SELECT DISTINCT person_home_ownership
FROM credit_risk2;

SELECT DISTINCT loan_intent
FROM credit_risk2;

-- Duplicates? Yes, 165

-- Remove duplicates --> 
SELECT *, ROW_NUMBER() OVER(PARTITION BY person_age, person_income, person_home_ownership, person_emp_length, loan_intent, loan_grade, loan_amount, loan_int_rate, loan_status, loan_percent_income, cb_person_default_on_file, cb_person_cred_hist_length) AS row_num
FROM credit_risk2; -- Table with row numbers tracking identical records across all columns --> duplicates are flagged with 2

WITH cte AS
(SELECT *, ROW_NUMBER() OVER(PARTITION BY person_age, person_income, person_home_ownership, person_emp_length, loan_intent, loan_grade, loan_amnt, loan_int_rate, loan_status, loan_percent_income, cb_person_default_on_file, cb_person_cred_hist_length ORDER BY credit_id) AS row_num
FROM credit_risk)
SELECT COUNT(*)
FROM cte
WHERE row_num > 1; -- shows all duplicates from the original credit_risk table (165 total)

-- > Delete duplicates --> create a temporary table that drops automatically when the MySQL session closes
DROP TEMPORARY TABLE IF EXISTS temp;
CREATE TEMPORARY TABLE temp
LIKE credit_risk2; -- temporary table mirroring credit_risk2 columns

ALTER TABLE temp
ADD row_num INT; -- column required for the next command

INSERT INTO temp
SELECT *, ROW_NUMBER() OVER(PARTITION BY person_age, person_income, person_home_ownership, person_emp_length, loan_intent, loan_grade, loan_amount, loan_int_rate, loan_status, loan_percent_income, cb_person_default_on_file, cb_person_cred_hist_length ORDER BY credit_id) AS row_num
FROM credit_risk2; -- flags duplicates using row_num and inserts them into temp table

SELECT credit_id
FROM temp
WHERE row_num >= 2; -- duplicates have a row_num of 2 or higher

DELETE FROM credit_risk2
WHERE credit_id IN (
    SELECT credit_id
    FROM temp
    WHERE row_num >= 2
); 			-- deletes all duplicate entries from credit_risk2

-- Data is now ready for analysis

SELECT COUNT(*) FROM credit_risk2; -- 32,581 - 165 duplicates = 32,416
USE credit_risk_dataset;

########### TASK 1 ###############

######## loan_status/loan_grades
DROP VIEW IF EXISTS loans_by_loan_grades;

CREATE VIEW loans_by_loan_grades AS
WITH cte AS (
SELECT loan_grade,
SUM(CASE WHEN loan_status=1 
	THEN 1
	ELSE 0
	END) AS defaults,
SUM(CASE WHEN loan_status=0 
	THEN 1
	ELSE 0
	END) AS not_defaulted,
COUNT(*) AS total_credit_count
FROM credit_risk2
GROUP BY loan_grade WITH ROLLUP
)
SELECT COALESCE(loan_grade, "Total") AS loan_grade, defaults, not_defaulted, total_credit_count, ROUND(defaults/total_credit_count*100,2) AS default_rate_in_percent
FROM cte; 


####################
-- loan_status/loan_amount
DROP VIEW IF EXISTS loans_amount_by_loan_grades;

CREATE VIEW loans_amount_by_loan_grades AS
WITH cte2 AS (
SELECT loan_grade,
SUM(CASE WHEN loan_status=1 
	THEN loan_amount
	ELSE 0
	END) AS loan_amount_defaults,
SUM(CASE WHEN loan_status=0 
	THEN loan_amount
	ELSE 0
	END) AS loan_amount_not_defaulted,
SUM(loan_amount) AS sum_total_loan_amount
FROM credit_risk2
GROUP BY loan_grade WITH ROLLUP
)
SELECT COALESCE(loan_grade, "Total") AS loan_grade, loan_amount_defaults, loan_amount_not_defaulted, sum_total_loan_amount, ROUND(loan_amount_defaults/sum_total_loan_amount*100,2) AS defaults_amount_percentage
FROM cte2; -- high loan amounts in D despite relatively high default rates


-- loan status/loan amount grouping
DROP VIEW IF EXISTS loan_amount_groups;

CREATE VIEW loan_amount_groups AS
SELECT amount_groups, defaults, not_defaulted, total_credits, default_rate_in_percent
FROM
(SELECT CASE
	WHEN loan_amount BETWEEN 0 AND 5000 THEN "Loan amount up to 5,000"
	WHEN loan_amount BETWEEN 5001 AND 10000 THEN "Loan amount between 5,001 and 10,000"
	WHEN loan_amount BETWEEN 10001 AND 15000 THEN "Loan amount between 10,001 and 15,000"
	WHEN loan_amount BETWEEN 15001 AND 20000 THEN "Loan amount between 15,001 and 20,000"
    ELSE "Over 20,000"
	END AS amount_groups,
SUM(CASE
	WHEN loan_status=1 THEN 1
	ELSE 0
	END) AS defaults,
SUM(CASE
	WHEN loan_status=0 THEN 1
	ELSE 0
	END) AS not_defaulted,
COUNT(*) AS total_credits,
ROUND(SUM(CASE
	WHEN loan_status=1 THEN 1
	ELSE 0
	END)/COUNT(*)*100,2) AS default_rate_in_percent
FROM credit_risk2
GROUP BY amount_groups
) AS t
ORDER BY CASE
WHEN amount_groups="Loan amount up to 5,000" THEN 1
WHEN amount_groups="Loan amount between 5,001 and 10,000" THEN 2
WHEN amount_groups="Loan amount between 10,001 and 15,000" THEN 3
WHEN amount_groups="Loan amount between 15,001 and 20,000" THEN 4
ELSE 5
END
; -- --> higher credit default rate above 15,000

## Implications:
-- > G is the main risk group, no credit should be granted to any customer here
-- > Credit grades A and B are secure
-- > F and E must be monitored
-- > D has high credit defaults --> reduce loan amounts
-- > Higher credit default rate starting from loan amount of 15,000


########
-- loan_status/loan_percent_income grouping
DROP VIEW IF EXISTS loan_percent_groups;

CREATE VIEW loan_percent_groups AS
SELECT COALESCE(income_percent_group, "Total") AS income_percent_group, defaults, not_defaulted, total_credits, default_rate_in_percent
FROM
(SELECT CASE
	WHEN loan_percent_income BETWEEN 0 AND 0.19 THEN "0 to 19 % of income"
	WHEN loan_percent_income BETWEEN 0.2 AND 0.29 THEN "20 to 29 % of income"
    WHEN loan_percent_income BETWEEN 0.3 AND 0.34 THEN "30 to 34 % of income"
    WHEN loan_percent_income BETWEEN 0.35 AND 0.39 THEN "35 to 39 % of income"
	WHEN loan_percent_income BETWEEN 0.4 AND 0.59 THEN "40 to 59 % of income"
	WHEN loan_percent_income BETWEEN 0.6 AND 0.79 THEN "60 to 79 % of income"
    ELSE "Over 80% of income"
	END AS income_percent_group,
SUM(CASE
	WHEN loan_status=1 THEN 1
	ELSE 0
	END) AS defaults,
SUM(CASE
	WHEN loan_status=0 THEN 1
	ELSE 0
	END) AS not_defaulted,
COUNT(*) AS total_credits,
ROUND(SUM(CASE
	WHEN loan_status=1 THEN 1
	ELSE 0
	END)/COUNT(*)*100,2) AS default_rate_in_percent
FROM credit_risk2
GROUP BY income_percent_group WITH ROLLUP
) AS t;
-- --> high credit defaults for individuals where the loan ratio exceeds 30% of income
### Implication ---> check A and B entries with more than 30% loan_percent_income for correct classification


#######
-- loan_status/person home ownership
DROP VIEW IF EXISTS loans_by_person_home_ownership;

CREATE VIEW loans_by_person_home_ownership AS
WITH cte AS (
SELECT person_home_ownership,
SUM(CASE WHEN loan_status=1 
	THEN 1
	ELSE 0
	END) AS defaults,
SUM(CASE WHEN loan_status=0 
	THEN 1
	ELSE 0
	END) AS not_defaulted,
COUNT(*) AS total_credit_count
FROM credit_risk2
GROUP BY person_home_ownership
)
SELECT person_home_ownership, defaults, not_defaulted, total_credit_count, ROUND(defaults/total_credit_count*100,2) AS default_rate_in_percent
FROM cte; 
-- > nearly double the defaults for renters compared to individuals with mortgages (31% vs. 12%), very low defaults for outright owners


#################
-- loan_status/loans_by_prior_defaults
DROP VIEW IF EXISTS loans_by_prior_defaults;

CREATE VIEW loans_by_prior_defaults AS
WITH cte AS (
SELECT cb_person_default_on_file,
SUM(CASE WHEN loan_status=1 
	THEN 1
	ELSE 0
	END) AS defaults,
SUM(CASE WHEN loan_status=0 
	THEN 1
	ELSE 0
	END) AS not_defaulted,
COUNT(*) AS total_credit_count
FROM credit_risk2
GROUP BY cb_person_default_on_file
)
SELECT cb_person_default_on_file AS cb_person_default_on_file, defaults, not_defaulted, total_credit_count, ROUND(defaults/total_credit_count*100,2) AS default_rate_in_percent
FROM cte;  -- -- > Individuals with prior defaults are twice as likely to fail again (38% vs. 18%)


######## Misclassified Loans - Task 1 ########
SELECT credit_id, loan_grade, loan_percent_income
FROM credit_risk2
WHERE loan_percent_income > 0.4 AND loan_grade IN ("A","B")
ORDER BY loan_percent_income DESC; -- --> 656 high-risk customers hidden in rating classes A and B

SELECT *
FROM credit_risk2
WHERE loan_grade="G"; -- 64

SELECT *
FROM credit_risk2
WHERE loan_percent_income > 0.7; --  9 entries over 70% income ratio --> reclassify all into Rating E or higher

SELECT *
FROM credit_risk2
WHERE loan_percent_income > 0.3
	AND loan_amount > 15000
    AND person_home_ownership IN ('RENT','OTHER')
    AND cb_person_default_on_file="Y"
	AND loan_grade !="G"; -- 200 records highly likely to default that should be classified into risk grade G
#######


####### Worth noting #######
SELECT COALESCE(loan_intent, "total") AS loan_intent, 
SUM(CASE WHEN loan_status=1 THEN 1 ELSE 0 END) AS defaults,
SUM(CASE WHEN loan_status=0 THEN 1 ELSE 0 END) AS not_defaulted,
COUNT(*) AS total_credits,
ROUND(SUM(CASE WHEN loan_status=1 THEN 1 ELSE 0 END)/COUNT(*)*100,2) AS default_rate_in_percent
FROM credit_risk2
GROUP BY loan_intent WITH ROLLUP; -- debt consolidation, medical, and home improvement default rates are above 25%


/*##### Task 1 Summary, Key Insights #####

- No primary key (PK) initially
- No date or timestamps provided
- No loan term duration data
- 165 duplicate records detected and dropped
- person_emp_length over 100 --> 2 clients, needs client confirmation --> changed to NULL
- 9,228 individuals were employed with an age between 15 and 18 --> check age verification processes
- NULL values in person_emp_length --> 887, significant volume --> needs resolution
- NULL values in loan_int_rate --> 3,095, almost 10%, highly significant volume, requires clarification
- Individuals over 100 years old --> 5 --> check with clients --> changed to NULL
- 1 Credit lists an income of 6,000,000 --> verify validity
- 9 loans assigned to individuals with over 1 million in income
- Debt consolidation, medical, and home improvement segments exhibit over a 25% default rate

- Key factors significantly shifting loan_status:
  - Credit grades A and B are reliable and secure
  - Grades F and E require active monitoring
  - Grade D presents massive losses --> decrease general loan amounts allowed
  - Drastic default jumps happen when loan weight exceeds 30% of individual income
  - Renter/Other categories display double the default occurrence vs. mortgages (31% vs 12%), lowest default risk from outright owners
  - Clients with prior default records default twice as frequently (38% vs. 18%)
  - Default rate risks multiply above loan amounts of 15,000 

- Incorrectly graded customers and loans that shouldn't have been authorized:
  - 656 high-risk consumers misclassified inside secure rating grades A and B
  - Risk Group G represents the critical risk core; lending to this group should be completely prohibited
  - 9 application records exceeding 70% income ratio weight --> elevate automatically to at least Grade E
  - 200 records matching high-default parameters that should be directly forced into Grade G
 */
 
 
USE credit_risk_dataset;

######## TASK 2 #################
-- risk_categories_all
DROP VIEW IF EXISTS risk_categories_all;

CREATE VIEW risk_categories_all AS
SELECT *,
CASE
-- VERY HIGH RISK
WHEN loan_grade="G" THEN "Very high risk, loan approval not recommended"
WHEN loan_grade IN ('E','F') 
AND loan_percent_income > 0.30 
AND person_home_ownership IN ('RENT','OTHER') 
AND cb_person_default_on_file="Y" 
AND loan_amount > 15000 THEN "Very high risk, loan approval not recommended"
-- HIGH RISK
WHEN loan_percent_income > 0.30 THEN 'High risk'
WHEN loan_amount > 15000 AND (person_home_ownership IN ('RENT','OTHER') OR cb_person_default_on_file="Y") THEN 'High risk'
WHEN loan_grade IN ('E','F') AND (person_home_ownership IN ('RENT','OTHER') OR cb_person_default_on_file="Y") THEN 'High risk'
-- LOW RISK
WHEN loan_grade IN ('A', 'B') AND loan_percent_income <= 0.30 THEN 'Low risk'
WHEN person_home_ownership="OWN" AND loan_percent_income <= 0.30 AND cb_person_default_on_file="N" AND loan_amount < 15000 THEN 'Low risk'
-- MEDIUM RISK
WHEN loan_amount > 15000 AND loan_percent_income <= 0.30 AND (person_home_ownership IN ('RENT','OTHER') OR cb_person_default_on_file="Y") THEN 'Medium risk'
ELSE 'Medium risk' END AS risk_category
FROM credit_risk2;

-- Distribution
DROP VIEW IF EXISTS risk_categories_distribution;

CREATE VIEW risk_categories_distribution AS
SELECT risk_category,
SUM(CASE WHEN loan_status=1 THEN 1 ELSE 0 END) AS defaults,
SUM(CASE WHEN loan_status=0 THEN 1 ELSE 0 END) AS not_defaulted,
COUNT(*) AS total_credits,
ROUND(SUM(CASE WHEN loan_status=1 THEN 1 ELSE 0 END)/COUNT(*)*100,2) AS default_rate_in_percent
FROM risk_categories_all
GROUP BY risk_category
ORDER BY CASE
	WHEN risk_category="Low risk" THEN 1
    WHEN risk_category="Medium risk" THEN 2
    WHEN risk_category="High risk" THEN 3
    ELSE 4 END;


########### Additional Task (Scoring) ############
DROP VIEW IF EXISTS scored_all;

CREATE VIEW scored_all AS
WITH scored AS
(
  SELECT *,
    (CASE WHEN loan_percent_income < 0.10 THEN 0
          WHEN loan_percent_income < 0.20 THEN 1
          WHEN loan_percent_income < 0.30 THEN 2
          WHEN loan_percent_income < 0.40 THEN 4
          ELSE 9 END)
    +
    (CASE WHEN person_home_ownership IN ('MORTGAGE','OWN') THEN 0 ELSE 2 END)
    +
    (CASE WHEN cb_person_default_on_file = 'Y' THEN 1 ELSE 0 END)
    +
    (CASE WHEN loan_amount > 15000 THEN 1 ELSE 0 END)
    AS risk_score
  FROM credit_risk2
)
SELECT *,
  CASE WHEN risk_score <= 1 THEN 'A_new'
       WHEN risk_score <= 4 THEN 'B_new'
       WHEN risk_score <= 6 THEN 'C_new'
       WHEN risk_score <= 8 THEN 'D_new'
       ELSE 'E_new' END AS new_grade
FROM scored;

SELECT * FROM scored_all;

-- Distribution Evaluation
DROP VIEW IF EXISTS scored_distribution;

CREATE VIEW scored_distribution AS
SELECT COALESCE(new_grade, "Total") AS new_grade,
SUM(CASE WHEN loan_status=1 THEN 1 ELSE 0 END) AS defaults,
SUM(CASE WHEN loan_status=0 THEN 1 ELSE 0 END) AS not_defaulted,
COUNT(*) AS total_credits,
ROUND(SUM(CASE WHEN loan_status=1 THEN 1 ELSE 0 END)/COUNT(*)*100,2) AS default_rate_in_percent
FROM scored_all
GROUP BY new_grade WITH ROLLUP
ORDER BY new_grade;
