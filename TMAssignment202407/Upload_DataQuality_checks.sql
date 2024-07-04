CREATE DATABASE NordeaTM;

USE NordeaTM;

CREATE TABLE transactions (
	CustomerID int
	,TransactionSign VARCHAR(10)
	,TransactionAmount int -- after a first exploration via Notepad++ it appears there are no deciamls in the dataset.
	,TransactionCountry VARCHAR(2)
); 

BULK INSERT transactions
FROM 'C:\Users\...\transactions.txt' -- update the path if needed
WITH (
	FIELDTERMINATOR = ';',
	ROWTERMINATOR = '\n',
	FIRSTROW = 1
);


SELECT TOP 1 *
FROM transactions

-- Checking compleateness of import:
SELECT
	COUNT(*) -- total records
	, SUM(ABS(TransactionAmount)) --total amounts of transactions in the dataset (in absolute values)
FROM transactions;

-- All 155181 records imported
-- Total amount transacted in the dataset 779.024.847

-- Checking the number of occurence of each CustomerID & the total number of customers
SELECT 
	CustomerID
	, COUNT(CustomerID) customer_records
FROM transactions
GROUP BY CustomerID
ORDER BY customer_records DESC;
-- 10k customers total

-- Checking the formal correctnes of customer IDs:
SELECT DISTINCT
	CustomerID
FROM transactions
WHERE CustomerID < 1
-- There is a CustomerID '0'.

-- Checking if there is a transactional history for such ID:
SELECT *
FROM transactions
WHERE CustomerID = 0
ORDER BY TransactionAmount DESC
-- Apparently there are #19 transactions for ID 0. These transactions do not look like techincal transactions (e.g. same amount and opposit sign).
-- To check with data/process owner, or clients DB.

-- Checking the min-max value in the Amount column:
SELECT
	TransactionSign
	,MIN(TransactionAmount) min_transaction_amount
	,MAX(TransactionAmount) max_transaction_amount
FROM transactions
GROUP BY TransactionSign;

-- Looks like there are negative transactions both in the Credit and Debit sign. 
-- It's necessary to understand better the underlying business logic: could be refunds (sometimes partial, or some kind of errors/noise)

SELECT
	TransactionSign
	, MIN(TransactionAmount) min_transaction_amount
	, MAX(TransactionAmount) max_transaction_amount
	, SUM(ABS(TransactionAmount)) total_abs_amount
	, count(TransactionSign) num_transactions
FROM transactions
WHERE TransactionAmount <= 0
GROUP BY TransactionSign;

-- It appears there are 102 transactions below or equal 0, in a dataset having more than 150k records (aprox. 0,07% of total records). 
-- If those are refunds, it looks a bit souspeciously low as a number to me.
-- Total amount of transactions below 0 = 53.115 (aprox. 0,01% of total amounts)


-- Checking for concentrations of such transactions
-- by customers and countries
SELECT 
	CustomerID
	,TransactionCountry
	,COUNT(CustomerID) num_records
FROM transactions
WHERE TransactionAmount < 0
GROUP BY 
	CustomerID
	,TransactionCountry
HAVING COUNT(CustomerID) > 1
ORDER BY num_records DESC;

-- Looks like only 2 CustomerID have more then 1 transaction of this kind

-- by amount
SELECT 
	TransactionAmount
	,Count(TransactionAmount) num_records
FROM transactions
WHERE TransactionAmount < 0
GROUP BY 
	TransactionAmount
HAVING COUNT(TransactionAmount) > 1
ORDER BY num_records DESC;

-- Since those transactions are very few both in number both in amount, we are excluding them from the dataset and from the investigation.

-- Checking if identified transactions are made by the same CustomerID, or could appear in any other way related (e.g. mutual exchange)
SELECT *
FROM transactions
WHERE TransactionAmount in (-338,-37)

-- Really looks just like some kind of dirt in the dataset. To be checked with process owners/business if there is a logic behind. If not: exclude from the analysis.
-- Checking for transactions with 0 amount:
SELECT
	TransactionSign
	, COUNT(TransactionSign) num_transactions
FROM transactions
WHERE TransactionAmount = 0
GROUP BY TransactionSign;
-- OK: no such transactions

-- Checking for missing values:
SELECT
	*
FROM transactions
WHERE CustomerID IS NULL
	OR TransactionSign IS NULL
	OR TransactionAmount IS NULL
	OR TransactionCountry IS NULL;
-- OK: No missing values

-- Checking distribution by countries of the transactions:
SELECT 
	TransactionCountry
	, COUNT(TransactionCountry) num_transactions
FROM vw_transactions
GROUP BY TransactionCountry;
-- Mostrly Nordics evenly distributed. Some transactions with Romania and just a couple with PL, CY, RU

-- There are no date fields, so no checks are necessary

-- Checking the median & average to determine skewness of the dataset.
SELECT
	*
FROM transactions
-- performed in excel.
-- AVG transaction amount: 5019,420013
-- median transaction amount: 5001
-- THE DATASET LOOKS FAIRLY BALANCED

--Preparing a version of transactions.txt with no transactions >0 amount
CREATE VIEW vw_transactions AS
SELECT *
FROM transactions
WHERE TransactionAmount > 0;


