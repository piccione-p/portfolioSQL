drop table if exists #received
drop table if exists #expected
drop table if exists #expected_estinti

declare @dataFine date = '2022-01-31'; -- inserire la fine del mese di riferimento
declare @datainizio date = dateadd(day,1,eomonth((dateadd(month, -1, @dataFine)))); -- viene calcolato in automatico l'inizio del mese di riferimento
declare @IdIstituzionale int = 4731;

select -- le rate expected coincidono con il piano di ammortamento: PRESTITI ESTINTI ANTICIPATAMENTE
	loan_id
	, [Principal expected in period]
	, [Interest expected in period]
	, Cashflow_reference_date
into #expected_estinti
from 
	( -- la sub select è necessaria per rimuovere le rate di incasso liquidazione MCC dalle somme expected. A differenza delle estinzioni anticipate, queste rate non hanno un flag specifico.
	select 
		pre.id AS loan_id
		, rp.QuotaCapitale AS 'Principal expected in period'
		, rp.QuotaInteressi + rp.Preammortamento AS 'Interest expected in period'
		, rp.scadenza AS Cashflow_reference_date -- le data in cui le rate sono expected coincide con la scadenza della stessa rata
		, rp.Stato
		, ROW_NUMBER() over(partition by rp.idprestito, rp.stato order by scadenza DESC) AS rimozione -- necessario per eliminare l'ultima rata in stato 20 (per le liquidazioni). Sia per le liquidazioni sia per le estinzioni anticipate, l'ultima rata in stato 20 è quella di chiusura con tutta la somma  relativa al prestito, questa non va considerata come rata expected, ma solo come received
	from VW_P2P_Prestito_Lender pre
		inner join P2P_RataPrestito rp -- piano di ammortamento
			on pre.Id = rp.IdPrestito
				and rp.Stato in (0, 20) -- nei prestiti estinti anticipatamente, si fa riferimento al piano non più attuale (rate in stato 0), oppure a quelle già pagate nello stesso mese della estinzione anticipata
				and rp.Scadenza between @datainizio and @dataFine -- la scadenza della rata attesa deve essere all'interno del mese di riferimento
		left join (
					select *
					, ROW_NUMBER() over (partition by idprestito order by datavariazione DESC) AS ordine
					from P2P_PrestitoStoricoStati 
					) ss -- ripesco l'ultimo stato del prestito, per differenziare le rate dei prestiti morti
						on pre.Id = ss.IdPrestito
							and ss.ordine = 1 -- l'ultimo stato in cui si trova il prestito
	where IdIstituzionale = @IdIstituzionale
		and (ss.CodiceStato in (91/*estinto anticipatamente*/, 93/*Liquidato MCC*/) -- l'estinzione anticipata/liquidazione MCC deve essere avventua nel mese di riferimento
				and ss.DataVariazione between @datainizio and @dataFine)
	--group by pre.Id -- rimosso: in caso di pagamenti multipli con una cessione nel mezzo, si perde la possibilità di distinguere a quali soggetti vanno imputati i diversi pagamenti
		/*and rp.EstinzioneAnticipata = 0*/ --  non devono essere considerate come expectred le somme di una estinzione anticipata
	) tab
where not (stato = 20 and rimozione = 1)

select -- le rate expected coincidono con il piano di ammortamento: PRESTITI NON ESTINTI ANTICIPATAMENTE
	pre.id AS loan_id
	, rp.QuotaCapitale AS 'Principal expected in period'
	, rp.QuotaInteressi + rp.Preammortamento AS 'Interest expected in period'
	, rp.scadenza AS Cashflow_reference_date -- le data in cui le rate sono expected coincide con la scadenza della stessa rata
into #expected
from VW_P2P_Prestito_Lender pre
	inner join P2P_RataPrestito rp
		on pre.Id = rp.IdPrestito
		and rp.Stato <> 0 -- solo rate attuali (cancellato, non pescherebbe l'expected delle estinzioni anticipate)
			and rp.Scadenza between @datainizio and @dataFine -- la scadenza della rata attesa deve essere all'interno del mese di riferimento
	left join (
				select *
				, ROW_NUMBER() over (partition by idprestito order by datavariazione DESC) AS ordine
				from P2P_PrestitoStoricoStati 
				) ss -- ripesco l'ultimo stato del prestito, per differenziare le rate dei prestiti morti
					on pre.Id = ss.IdPrestito
						and ss.ordine = 1 -- l'ultimo stato in cui si trova il prestito
where IdIstituzionale = @IdIstituzionale
	and ss.CodiceStato not in (91/*estinto anticipatamente*/, 93/*Liquidato MCC*/, 94/*Default*/ /*,80 Incagliato*/ )	-- i record riferiti a rate di prestiti non più vivi sono esclusi,	
--group by pre.Id -- rimosso: in caso di pagamenti multipli con una cessione nel mezzo, si perde la possibilità di distinguere a quali soggetti vanno imputati i diversi pagamenti


select -- le rate ricevute coincidono con quanto è stato effettivamente pagato
	pre.Id AS loan_id
	, SUM(rr.QuotaCapitale) AS 'Principal received In Period'
	, SUM(rr.QuotaInteressi) AS 'Interest received In Period'
	, MAX(rr.[DateTime]) AS Cashflow_reference_date -- le data in cui le rate sono ricevute coincide con la data di incasso
	, AVG(cess.IdPrestatore) AS IdPrestatore
into #received
from VW_P2P_Prestito_Lender pre
	inner join P2P_RientroRata rr -- rate pagate con relativo dettaglio
		on pre.id = rr.IdPrestito
			and CAST(rr.[DateTime] AS DATE) between @datainizio and @dataFine -- solo rate pagate nel mese di riferimento
	left join ( --la join è necessaria per separare le somme pagate a un soggetto diverso dal detentore del prestito a fine mese di riferimento (cfr. cessioni)
				select 
					ROW_NUMBER() over (partition by idprestito order by datacessione DESC) AS ordine
					, *
				from P2P_RichiesteCessioneCrediti
				where DataCessione is not null
					and IdPrestatore = @IdIstituzionale
				) cess
		on cess.IdPrestito = pre.Id 
			and ordine = 1 -- solo l'ultima cessione è rilevante
			and DataCessione > rr.[DateTime] -- la cessione è avvenuta dopo la data di pagamento: i fondi vanno al soggetto di cui si estrae il flusso
where IdIstituzionale = @IdIstituzionale
	OR cess.IdPrestatore = @IdIstituzionale
group by pre.Id

select 
	ROW_NUMBER() OVER(ORDER BY pre.id) AS CashFlow_id
	, pre.id AS loan_id
	, FORMAT(ISNULL(MAX(r.Cashflow_reference_date), MAX(ex.Cashflow_reference_date)), 'dd/MM/yyyy') AS 'Cashflow_reference_date'
	, '' AS 'Cashflow type'
	, FORMAT(ISNULL(SUM(IIF(pre.stato in (91, 93), exes.[Principal expected in period], ex.[Principal expected in period])),0),'0.00') AS 'Principal expected in period'
	, FORMAT(ISNULL(SUM(r.[Principal received In Period]),0),'0.00') AS 'Principal received In Period'
	, FORMAT(ISNULL(SUM(IIF(pre.stato in (91, 93), exes.[Interest expected in period],  ex.[Interest expected in period])),0),'0.00') AS 'Interest expected in period'
	, FORMAT(ISNULL(SUM(r.[Interest received In Period]),0),'0.00') AS 'Interest received In Period'
	, '0.00' AS 'Late Fees Received in Period'
	, ISNULL(
			(select 
				sum(r.QuotaCapitale) 
			from p2p_rientrorata r 
			where r.idprestito = pre.id)
			,'0,00') as 'Cumulative Principal Received'
	, ISNULL(
			(select 
				sum(r.QuotaInteressi)
			from p2p_rientrorata r 
			where r.idprestito = pre.id)
			,'0,00') as 'Cumulative Interest Received'
	, '0.00' AS 'Cumulative Late Fees Received'
	, FORMAT(ISNULL(
			(select 
				QuotaCapitale 
			from P2P_LiquidazioneMCC mcc
			where mcc.IdPrestito = pre.Id)
			,'0.00'),'0.00') AS 'Recovery_net'
from VW_P2P_Prestito_Lender pre
	left join #expected ex -- left, in quanto i dati sulle rate expected sono da passare SOLO in caso di effettivi pagamenti nel periodo di riferimento
		on pre.id = ex.loan_id
	left join #expected_estinti exes -- left, in quanto i dati sulle rate expected sono da passare SOLO in caso di effettivi pagamenti nel periodo di riferimento
		on pre.Id = exes.loan_id
	inner join #received r
		on pre.Id = r.loan_id
where ISNULL(r.IdPrestatore, pre.IdIstituzionale) = @IdIstituzionale
group by pre.id
