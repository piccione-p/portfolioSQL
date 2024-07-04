--creating the list of High Risk Countries present in the dataset
CREATE TABLE #HRCountries
(CountryName VARCHAR(2));
INSERT INTO #HRCountries
VALUES ('RO');
--------------------
SELECT *
FROM #HRCountries
--------------------

-- Cheking countries in the dataset
SELECT
	TransactionCountry
	, COUNT(TransactionCountry) num_transactions
FROM transactions
GROUP BY TransactionCountry
ORDER BY num_transactions DESC;

-- There are mostly nordic countries in the dataset (de facto equally distributed FI, DK, SE) 
-- + 331 transactions with RO and suspiciously low number of transactions with PL, CY, RU

-- Diving deeper on this "OUTLIERS"
SELECT
	*
FROM transactions
WHERE TransactionCountry in ('PL','CY','RU')

SELECT
	*
FROM transactions
WHERE TransactionCountry = 'RO'

-- Extracting clients (& their transactions), who have been transacting (among others) with the country "RO":
SELECT
	*
FROM transactions
WHERE CustomerID in
	(SELECT
		CustomerID
	FROM transactions
	WHERE TransactionCountry = 'RO')
ORDER BY CustomerID;

-- extracting clients who have been transacting with the outliers
SELECT
	*
FROM transactions
WHERE CustomerID in
	(SELECT
		CustomerID
	FROM transactions
	WHERE TransactionCountry in ('PL','CY','RU'))
ORDER BY CustomerID;


-- Preparing a temporary table with the grouping of transactions by customer, sign and country

SELECT
	CustomerID
	, TransactionSign
	, SUM(TransactionAmount) tot_amount /*remember to manage the negative amount transactions in final segmentation*/
	, COUNT(TransactionAmount) tot_transactions
	, AVG(TransactionAmount) avg_transaction_amount
--into #total_clients_transactions
FROM transactions
GROUP BY
	CustomerID
	, TransactionSign;

-- customers and their transactions split by country (amount and frequency)
SELECT 
	CustomerID
	, TransactionCountry
--	, TransactionSign
	, COUNT(TransactionCountry) num_transactions
	, SUM(TransactionAmount) sum_transactions /*remember to manage the negative amount transactions in final segmentation*/
FROM transactions
GROUP BY
	CustomerID
	, TransactionCountry
ORDER BY CustomerID

-- Looking for round transactions:
SELECT 
	CustomerID
--	, TransactionSign
	, COUNT(CustomerID) frequency_transactions
FROM transactions
WHERE TransactionAmount % 100 = 0 -- transactions round to the 100
--	AND TransactionAmount > 5000 --
GROUP BY
	CustomerID
--	, TransactionSign
ORDER BY frequency_transactions DESC
-- 1467 clients. Most round transactions per client: #3 (8 clients)
-- Does not look very relevant

SELECT 
	CustomerID
--	, TransactionSign
	, COUNT(CustomerID) frequency_transactions
FROM transactions
WHERE TransactionAmount % 100 = 0 -- transactions round to the 100
	AND TransactionAmount > 5000 -- transactions of higher amount then 5000 (reporting threshold in Italy)
GROUP BY
	CustomerID
--	, TransactionSign
ORDER BY frequency_transactions DESC
-- 718 clients. Most round transactions per client: 3 (5 clients)
-- Does not look very relevant

-- Checking frequency of transactions for the customers dataset (to be reworked in final version)
SELECT
	FrequencyCluster
	, COUNT(FrequencyCluster) num_customer
FROM
	(SELECT 
		CustomerID
		, COUNT(TransactionCountry) num_transactions
		, CASE
			WHEN COUNT(TransactionCountry) >20 THEN 5 -- transacting on average more than daily
			WHEN COUNT(TransactionCountry) =20 THEN 4 -- transacting on average daily
			WHEN COUNT(TransactionCountry) BETWEEN 13 AND 19 /*"21" since BETWEEN is inclusive of the limits*/ THEN 3 -- transacting on average between 3 times a week (excluded) and daily
			WHEN COUNT(TransactionCountry) BETWEEN 4 AND 12 /*"12" since BETWEEN is inclusive of the limits and 3*4 = 12*/ THEN 2 --  transacting on average up to 3 times a week
			WHEN COUNT(TransactionCountry) <4 THEN 1 -- transacting on average rarer than once a week
--			ELSE 999 -- in order to catch errors in the algorithm during tesets
		END FrequencyCluster
	-- into #TransactionFrequency
	FROM transactions
	GROUP BY
		CustomerID
	/*ORDER BY FrequencyCluster*/ ) tab
GROUP BY FrequencyCluster
ORDER BY FrequencyCluster
