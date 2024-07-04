-----PART I--------

--For the exercise the view vw_transactions will be used instead of the table transactions, since it has been cleaned of some dirty data

-- Preparing a Customer Risk Rating, based on transactions:
-- Customers are divided in low, medium, high risk, based on the following drivers:
-- a. Frequency of transactions in timespan (the higher, the riskier)
-- b. Nordics only/not only Nordics (Not only nordics - is riskier)
-- c. Transacting with High Risk Countries (or Russia): high risk
-- d. Outflows way higher than inflows: riskier
-- e. SUM Outflows similar to inflows
--DROPPED f. Frequent use of round numbers
-- g. One-to-Many / Many-to-One
-- h. Deviation from usual behavior


-- a. Clustering based on AVERAGE frequency of making transactions in the timespan (1 month as per assignment material)
/*assuming 20 workday per month*/
/*assuming a 5 day workweek*/
/*assuming a month with 4 weeks*/

-- buckets:
-- 1 - more than daily
-- 2 - daily
-- 3 - weekly
-- 4 - rarer than weekly


-- Preparing score buckets for final clustering in the mini-CRR
--a. Frequency of transactions in timespan (the higher, the riskier; starting from cluster 4, since cluster 3 looks like the normal behaviour)
SELECT 
	CustomerID
	, COUNT(TransactionCountry) num_transactions
	, CASE
		WHEN SUM(TransactionAmount) > 10000 AND COUNT(TransactionCountry) >500 THEN 6 -- Cluster 6: transacting on average 25&+ times a day
		WHEN SUM(TransactionAmount) > 10000 AND COUNT(TransactionCountry) BETWEEN 21 AND 499 THEN 5 -- Cluster 5: transacting on average more than daily
		WHEN SUM(TransactionAmount) > 10000 AND COUNT(TransactionCountry) =20 THEN 4 -- Cluster 4: transacting on average daily
		WHEN SUM(TransactionAmount) > 10000 AND COUNT(TransactionCountry) BETWEEN 13 AND 19 /*"21" since BETWEEN is inclusive of the limits*/ THEN 3 -- Cluster 3: transacting on average between 3 times a week (excluded) and daily
		WHEN SUM(TransactionAmount) > 10000 AND COUNT(TransactionCountry) BETWEEN 4 AND 12 /*"12" since BETWEEN is inclusive of the limits and 3*4 = 12*/ THEN 2 -- Cluster 2: transacting on average up to 3 times a week
		WHEN SUM(TransactionAmount) > 10000 AND COUNT(TransactionCountry) <4 THEN 1 -- Cluster 1: transacting on average rarer than once a week
--			ELSE 999 -- in order to catch errors in the algorithm during tesets
	END ScoreFrequency
INTO #TransactionFrequencyScore
FROM vw_transactions
GROUP BY
	CustomerID;
--ORDER BY ScoreFrequency DESC;

-- b. Nordics only/not only Nordics
-- & c. Transacting with High Risk Countries (or Russia):
/*Nordic countries are very close, so for the purpose of this investigation we will consider the Nordic market (SE, DK, FI) as a single entity*/

WITH AggregatedTransactions AS (
	SELECT
		CustomerID
		, TransactionCountry
		, COUNT(TransactionCountry) transaction_frequency
--		, SUM(TransactionAmount) transaction_sums_total
	FROM vw_transactions
	GROUP BY 
		CustomerID
		, TransactionCountry
)
SELECT 
	CustomerID
	, ISNULL(FI,0) FI
	, ISNULL(DK,0) DK
	, ISNULL(SE,0) SE
	, ISNULL(RO,0) RO
	, ISNULL(CY,0) CY
	, ISNULL(RU,0) RU
	, ISNULL(PL,0) PL
--	*
	, ISNULL(FI,0)+ISNULL(DK,0)+ISNULL(SE,0) nordics
	, ISNULL(FI,0)+ISNULL(DK,0)+ISNULL(SE,0)+ISNULL(RO,0)+ISNULL(CY,0)+ISNULL(RU,0)+ISNULL(PL,0) total_transactions
	, IIF(
		(ISNULL(FI,0)+ISNULL(DK,0)+ISNULL(SE,0)+ISNULL(RO,0)+ISNULL(CY,0)+ISNULL(RU,0)+ISNULL(PL,0)) /*total_transactions*/ - (ISNULL(FI,0)+ISNULL(DK,0)+ISNULL(SE,0)) /*nordics*/ = 0,
		1 /*NordicsOnly*/, 0/*NotNordicsOnly*/) NordicsOnly_check
	, IIF(
		ISNULL(RU,0)<>0,
		1 /*Transacting with Russia*/,0 /*Not transacting with Russia*/) Russia_check
	, IIF(
		ISNULL(RO,0)<>0,
		1/*Transacting with Romania*/,0 /*Not transacting with Romania*/) Romania_check
	, CAST(ISNULL(RO,0) AS float)/CAST((ISNULL(FI,0)+ISNULL(DK,0)+ISNULL(SE,0)+ISNULL(RO,0)+ISNULL(CY,0)+ISNULL(RU,0)+ISNULL(PL,0)) AS FLOAT) HRC_Trnsactions_Ratio
INTO #CountriesFlagsScore
FROM AggregatedTransactions
	PIVOT (
		SUM(transaction_frequency) FOR TransactionCountry IN ([FI],[DK],[SE],[RO],[CY],[RU],[PL])
	) AS Pivot_AggregatedTransactions;


-- d. Outflows way higher than inflows
-- & e. SUM Outflows similar to inflows
WITH AggregatedTransactions AS (
	SELECT
		CustomerID
		, TransactionSign
		, SUM(TransactionAmount) amount_transactions -- capire come gestire i valori negativi
	FROM vw_transactions
	GROUP BY
		CustomerID
		, TransactionSign
	)
SELECT
	*
	, IIF(CDRatio BETWEEN 0.98 AND 1.02, 1/*Credit similar to Debt*/,0) CDRatio_Around_1_flag -- This flag indicates that the outflows and inflows are almost equal /*357 clients total*/
INTO #CDRatioScore
FROM(
	SELECT
		CustomerID
		, ISNULL(Credit,0) Credit
		, ISNULL(Debit,0) Debit
		, CASE
			WHEN ISNULL(Debit,0) = 0 THEN 10 -- this is to prevent the "dividing by 0 issue, in the case there are compleatly no outflows. "10" is just a dummy high value in this case
			ELSE ISNULL(CAST(Credit AS FLOAT),0)/ISNULL(CAST(Debit AS FLOAT),0) -- when this is <1, it means the outflowing sums are higher than the inflowing ones
		END AS CDRatio -- Credit_to_Debit_Ratio
	FROM AggregatedTransactions
		PIVOT (
			SUM(amount_transactions) FOR TransactionSign IN ([Credit],[Debit])
		) AS Pivot_AggregatedTransactions) tab
ORDER BY CDRatio ASC;


-- f. Frequent use of round numbers
-- Droped: looks not relevant, after dataset exploration. Round number transactions are scarse(i.e. a very couple clients with more then 1 round transaction)

-- g. One-to-Many / Many-to-One

WITH AggregatedTransactions AS ( -- in order to have a count of the total transactions per Customer and sign in the dataset
	SELECT
		CustomerID
		, TransactionSign
		, COUNT(CustomerID) num_transactions
	FROM vw_transactions
	GROUP BY
		CustomerID
		, TransactionSign
	)
SELECT
	*
	, IIF(OtMRatio <=0.3, 1/*Possible One-to-Many*/,0) OtMRatio_flag -- This flag indicates the possibility of a One-to-Many Scheme /*198 clients total*/
	, IIF(MtORatio <=0.3, 1/*Possible Many-to-One*/,0) MtORatio_flag -- This flag indicates the possibility of a Many-to-One Scheme /*203 clients total*/
INTO #CDTRatioScore
FROM( -- subquery in order to keep the code cleaner and more readable, the alternative would have been the IIF and the CASE combined, making the code difficult to read
	SELECT
		CustomerID
		, ISNULL(Credit,0) Credit
		, ISNULL(Debit,0) Debit
		, CASE
				WHEN ISNULL(Debit,0) = 0 THEN 10 -- this is to prevent the "dividing by 0 issue, in the case there are compleatly no outflows. "10" is just a dummy high value in this case
				ELSE ISNULL(CAST(Credit AS FLOAT),0)/ISNULL(CAST(Debit AS FLOAT),0) -- when this is <1, it means the number of outflowing transactions is higher than the number of inflowing ones
			END AS OtMRatio -- One-to-Many_Probability_Ratio
		, CASE
				WHEN ISNULL(Credit,0) = 0 THEN 10 -- this is to prevent the "dividing by 0 issue, in the case there are compleatly no inflows. "10" is just a dummy high value in this case
				ELSE ISNULL(CAST(Debit AS FLOAT),0)/ISNULL(CAST(Credit AS FLOAT),0) -- when this is <1, it means the number of inflowing transactions is higher than the number of outflowing ones
			END AS MtORatio -- Many-to-One_Probability_Ratio
	FROM AggregatedTransactions
		PIVOT ( -- putting debit and credit on the same row, in order to perform calculations and joins
			SUM(num_transactions) FOR TransactionSign IN ([Credit],[Debit])
		) AS Pivot_AggregatedTransactions
	) tab;


-- h. Deviation from usual behavior
WITH standard_deviation_customers AS( -- calculating the standard deviation for transaction amount of the single customer, broken down by transaction sign
SELECT 
	CustomerID
	, TransactionSign
	, STDEVP(TransactionAmount) standard_dev
FROM vw_transactions
	GROUP BY 
		CustomerID
		, TransactionSign
)
,
average_transaction_customer AS ( -- calculating the average transaction amount of the single customer, broken down by transaction sign
SELECT -- calculating the avg transaction Credit/Debit for a client
	CustomerID
	, TransactionSign
--	, SUM(TransactionAmount) amount_transactions
--	, COUNT(TransactionAmount) num_transactions
	, SUM(CAST(TransactionAmount AS FLOAT))/COUNT(CAST(TransactionAmount AS FLOAT)) avg_amount_transaction
FROM vw_transactions
GROUP BY 
	CustomerID
	,TransactionSign
)
-- defining the threshold beyond which a transaction is considered unusual for the client
SELECT
	avrg.CustomerID
	, avrg.TransactionSign
	, avrg.avg_amount_transaction
	, standev.standard_dev
	, avrg.avg_amount_transaction + (standev.standard_dev*2) threshold_single_transaction -- the X sigma rule (here we are using the "2 sigma rule"): ref. "3 sigma rule" on Google
INTO #CustomerBehaviorDeviation
FROM average_transaction_customer avrg
	INNER JOIN standard_deviation_customers standev
		ON avrg.CustomerID = standev.CustomerID
			AND avrg.TransactionSign = standev.TransactionSign
--calculating - on the basis of the above set thresholds - the number of unusual transactions per signle customer
SELECT
	CustomerID
	, COUNT(CustomerID) total_num_transactions
	, SUM(transaction_unusual_alert) num_unusual_transactions
INTO #CustomerUnusualAlerts
FROM(
	SELECT
		tr.CustomerID
		, tr.TransactionSign
		, IIF(tr.TransactionAmount >= cbdev.threshold_single_transaction, 1, 0) transaction_unusual_alert
		, cbdev.threshold_single_transaction - tr.TransactionAmount deviation_amount
	FROM
		transactions tr
			LEFT JOIN #CustomerBehaviorDeviation cbdev
				ON tr.CustomerID = cbdev.CustomerID
					AND tr.TransactionSign = cbdev.TransactionSign) dev_beh_tab
GROUP BY 
	CustomerID
--ORDER BY num_unusual_transactions DESC


-- Customers present in the transactions:
SELECT
	DISTINCT CustomerID
INTO #customerbase
FROM vw_transactions

-- Combining together the mini-CRR: checking the results
SELECT
	cb.CustomerID
	, *
FROM #customerbase cb -- left joining all the temporary tables, in order to avoid loosing CustomerIDs, in the case the ID is missing in one of the temporary tables
	LEFT JOIN #TransactionFrequencyScore sctrfr
		ON cb.CustomerID = sctrfr.CustomerID
	LEFT JOIN #CountriesFlagsScore sccfl
		ON cb.CustomerID = sccfl.CustomerID
	LEFT JOIN #CDRatioScore cdr
		ON cb.CustomerID = cdr.CustomerID
	LEFT JOIN #CDTRatioScore cdtr
		ON cb.CustomerID = cdtr.CustomerID
	LEFT JOIN #CustomerUnusualAlerts cual
		ON cb.CustomerID = cual.CustomerID;

-- Combining and attributing points, in order to determine Risk Rating (for results ref. to xlsx file: CRR_final)
SELECT
	*
	, (TransactionFrequencyScore + NotNordicsOnlyFlag + HRCFlag + RussiaFlag + HighOutflowsFlag + CDRatioFlag + One_to_Many_Risk_Flag + Many_to_One_Risk_Flag + UnusualTransactionsScore) TOTAL_Score -- the final CRR score is the sum of the single risk factors
	, CASE 
		WHEN TransactionFrequencyScore + NotNordicsOnlyFlag + HRCFlag + RussiaFlag + HighOutflowsFlag + CDRatioFlag + One_to_Many_Risk_Flag + Many_to_One_Risk_Flag + UnusualTransactionsScore <1 THEN 'Low' -- there are 7021 (70,21% of total) clients in this segment
		WHEN TransactionFrequencyScore + NotNordicsOnlyFlag + HRCFlag + RussiaFlag + HighOutflowsFlag + CDRatioFlag + One_to_Many_Risk_Flag + Many_to_One_Risk_Flag + UnusualTransactionsScore BETWEEN 1 AND 2 THEN 'Medium-Low' -- there are 2851 (28,51% of total) clients in this segment
		WHEN TransactionFrequencyScore + NotNordicsOnlyFlag + HRCFlag + RussiaFlag + HighOutflowsFlag + CDRatioFlag + One_to_Many_Risk_Flag + Many_to_One_Risk_Flag + UnusualTransactionsScore BETWEEN 3 AND 5 THEN 'Medium-High' -- there are 126 (1,26% of total) clients in this segment
		WHEN TransactionFrequencyScore + NotNordicsOnlyFlag + HRCFlag + RussiaFlag + HighOutflowsFlag + CDRatioFlag + One_to_Many_Risk_Flag + Many_to_One_Risk_Flag + UnusualTransactionsScore >5 THEN 'High' -- there are 2 (0,02% of total) clients in this segment
	END AS Risk_Segment -- based on the total score just calculated, customers are sorted in risk segments from Low Transactional Risk to High Transactional Risk
INTO #CRR
FROM(
	SELECT
		cb.CustomerID
		, CASE 
			WHEN sctrfr.ScoreFrequency IS NULL THEN 0 -- not meeting the minumum transactions criteria is equal to a lower risk behavior
			WHEN sctrfr.ScoreFrequency in (1,2,3) THEN 0 -- transacting up to 3 times a week is considered low risk behaviour
			WHEN sctrfr.ScoreFrequency = 4 THEN 1
			WHEN sctrfr.ScoreFrequency = 5 THEN 2
			WHEN sctrfr.ScoreFrequency = 6 THEN 3 
		END AS TransactionFrequencyScore
		, CASE
			WHEN sccfl.NordicsOnly_check = 1 THEN 0 -- transacting only with Nordic countries is considered lower risk behaviour
			WHEN sccfl.NordicsOnly_check = 0 THEN 1
		END AS NotNordicsOnlyFlag
		, CASE
			WHEN sccfl.HRC_Trnsactions_Ratio >= 0.3 /*ratio of transaction with Romania to Total transactions*/THEN 3 -- transacting frequently with Romania (High Risk Country) is a higher risk behaviour
			WHEN sccfl.HRC_Trnsactions_Ratio > 0.01 /*ratio of transaction with Romania to Total transactions*/THEN 1 -- transacting occasionally with Romania (High Risk Country) is not a risky behaviour, but deserves more attention then 0
			ELSE 0
		END AS HRCFlag
		, CASE
			WHEN sccfl.Russia_check = 1 THEN 3 -- transacting with Russia (Highly sanctioned country, although not officialy listed as High Risk) is a higher risk behaviour
			ELSE 0
		END AS RussiaFlag
		, CASE
			WHEN cdr.CDRatio <=0.3 THEN 1 -- outflows to inflows ratio of 0,3 is considered a higher risk behaviour
			ELSE 0
		END AS HighOutflowsFlag
		, CASE
			WHEN cdr.CDRatio_Around_1_flag = 1 THEN 1 -- having inflows similar to outflows is considered a higher risk behaviour
			ELSE 0
		END AS CDRatioFlag
		, CASE
			WHEN cdtr.OtMRatio_flag = 1 THEN 1 -- having a ratio of incoming transactions to outgoing transactions of <=0,3 is considered a higher risk behaviour
			ELSE 0
		END AS One_to_Many_Risk_Flag
		, CASE	
			WHEN cdtr.MtORatio_flag = 1 THEN 1 -- having a ratio of outgoing transactions to incoming transactions of <=0,3 is considered a higher risk behaviour
			ELSE 0
		END AS Many_to_One_Risk_Flag
		, CASE
			WHEN cual.num_unusual_transactions = 0 THEN 0
			WHEN cual.num_unusual_transactions BETWEEN 1 AND 2 THEN 1
			WHEN cual.num_unusual_transactions >2 THEN 3
		END AS UnusualTransactionsScore
	FROM #customerbase cb -- left joining all the temporary tables, in order to avoid loosing CustomerIDs, in the case the ID is missing in one of the temporary tables
		LEFT JOIN #TransactionFrequencyScore sctrfr
			ON cb.CustomerID = sctrfr.CustomerID
		LEFT JOIN #CountriesFlagsScore sccfl
			ON cb.CustomerID = sccfl.CustomerID
		LEFT JOIN #CDRatioScore cdr
			ON cb.CustomerID = cdr.CustomerID
		LEFT JOIN #CDTRatioScore cdtr
			ON cb.CustomerID = cdtr.CustomerID
		LEFT JOIN #CustomerUnusualAlerts cual
			ON cb.CustomerID = cual.CustomerID) tab;

/*select *
from #CRR
where customerid = 8816*/

-----PART II--------
--Identify a minimum of 5 customer IDs connected to transactions that do not fit into the customer's own typical behavior, 
--and/or into the respective customer segments typical behavior. For each of these customers, also explain the reason behind its selection

SELECT /*TOP 5*/ -- the reasoning for the identification is: TOP 5 transactions deviating the heaviest from the customer usual behavior. 5 is the minimum assignment.
	tr.CustomerID
	, tr.TransactionSign
	, tr.TransactionAmount
	, tr.TransactionCountry
	, cbdev.threshold_single_transaction
	, IIF(tr.TransactionAmount >= cbdev.threshold_single_transaction, 1, 0) transaction_unusual_alert
	, cbdev.threshold_single_transaction - tr.TransactionAmount deviation_amount -- the way we are identifing such scenario: the strongest deviation from the avg+2 standard deviations
	, crr.Risk_Segment
	, crr.TOTAL_Score
FROM
	vw_transactions tr
		LEFT JOIN #CustomerBehaviorDeviation cbdev -- reutilizing the table from: h. Deviation from usual behavior
			ON tr.CustomerID = cbdev.CustomerID
				AND tr.TransactionSign = cbdev.TransactionSign
		LEFT JOIN #CRR crr -- using Customer Risk Rating
			ON tr.CustomerID = crr.CustomerID
WHERE cbdev.threshold_single_transaction - tr.TransactionAmount <0
ORDER BY deviation_amount ASC



-----PART III--------
--Romania has been recently classified as a high-risk country. Given the rule "Total Monthly Incoming transaction amount from Romania > threshold_value",
--recommend an amount threshold for each segment (identified in step 1) to find potential monthly unusual behavior 

-- Creating the table of total transactions with Romania by customer (elaborated in excel: refer to Romania_rule.xlsx)
SELECT
	rotr.CustomerID
	, SUM(rotr.TransactionAmount)TransactionAmount -- the rule is TOTAL monthly incoming, so we group by customer
	, crr.Risk_Segment
INTO #RomaniaTransactions
FROM vw_transactions rotr
	left join #CRR crr
		on rotr.CustomerID = crr.CustomerID
WHERE TransactionCountry = 'RO'
	AND TransactionSign = 'Credit' -- The rule is ment to work only with Incoming transactions
GROUP BY 
	rotr.CustomerID
	, crr.Risk_Segment

-----PART IV--------
-- Customer IDs triggering the new rule.
-- The amounts have been defined in the Romania_rule.xlsx
SELECT 
	*
FROM #RomaniaTransactions 
WHERE 
	Risk_Segment ='High' AND  TransactionAmount > 0
	OR Risk_Segment ='Medium-High' AND  TransactionAmount > 19120
	OR Risk_Segment ='Medium-Low' AND  TransactionAmount > 11646
--	OR Risk_Segment ='Low' AND  TransactionAmount > -- this part has been frozen since according to the CRR model currently it's virtually not possible to have a customer transacting with Romania in a Low risk segment

