--ID istituzionali

DECLARE @idistituzionale int = 5091;


WITH 
--1. calcolo del capitale pagato totale per orgni rata e del capitale residuo per rata 
pagato_totalerata
AS
(
select 
	ra.IdPrestito
	, ra.NumeroRata
	, ra.Scadenza
	, ra.QuotaCapitale
	, pag.capitale_pagato_totalerata
	, (ra.QuotaCapitale-pag.capitale_pagato_totalerata) capitale_residuo
	, pag.interessi_pagati_totalerata
	, (ra.QuotaInteressi-pag.interessi_pagati_totalerata) interessi_residui
	, data_pagamento
from P2P_RataPrestito ra
	inner join (select 
					IdPrestito
					, NumeroRata
					, sum(QuotaCapitalePagata) capitale_pagato_totalerata
					, sum(QuotaInteressiPagata) interessi_pagati_totalerata
					, max([Date]) data_pagamento-- data dell'ultimo pagamento riferibile alla rata
				from P2P_RataPrestito_Pagamento
				group by IdPrestito, NumeroRata) pag 
		on ra.IdPrestito = pag.IdPrestito 
		and ra.NumeroRata = pag.NumeroRata
--order by IdPrestito,NumeroRata
)
--2. calcolo del capitale residuo da pagare per ogni rata
, capitale_scaduto AS
(
select
	IdPrestito
	,capitale_residuo
	,scadenza
from pagato_totalerata
where Scadenza < getdate() and capitale_residuo <> 0 -- meglio mettere "capitale_residuo > 0"?
)
--3. calcolo degli interessi residui da pagare per ogni rata
, interessi_scaduti AS
(
select
	IdPrestito
	,interessi_residui
	,scadenza
from pagato_totalerata
where Scadenza < getdate() and interessi_residui <> 0
)

--, capitale_residuo AS
--(

--)

SELECT
	'RES' AS 'TIPO'
	, CASE pre.IdIstituzionale
					WHEN 5091 then '208' -- IFRIT SPV
					ELSE ''
		END AS 'SOCIETA'''
	--, CASE pre.IdIstituzionale
	--				WHEN 4731 then '1855'
	--				WHEN 4990 then '1967'
	--				WHEN 4997 then '1965'
	--				ELSE ''
	--	END AS 'PORTAFOGLIO'
	, 2075 AS 'PORTAFOGLIO'
	, FORMAT(ric.IdPmi,'0100000000000000') as 'NDG DEBITORE 130 SERVICING'
	, ric.Nome AS 'NOMINATIVO DEBITORE'
	, pre.id as 'CODICE PRATICA 130 SERVICING'
	, IIF(ra.quotacapitale = 0 and ra.ordine <= pre.durata_preammortamento_finanziario, 'P', 'A') AS 'FLAG PREAMM./AMMORT.'
	, ra.Ordine AS 'NUMERO RATA'
	, CAST(ra.Scadenza AS DATE) AS 'DATA SCADENZA/EVENTO'
	, DATEFROMPARTS(YEAR(dateadd(month,-1,ra.scadenza)), month(dateadd(month,-1,ra.scadenza)), 1) AS 'DATA INIZIO MATURAZIONE RATA'
	, FORMAT(ra.quotacapitale, '0.0000', 'it-it') AS 'QUOTA CAPITALE'
	, FORMAT(ra.quotainteressi + ra.Preammortamento, '0.0000', 'it-it') AS 'QUOTA INTERESSI'
	, CAST('0' as money) AS 'SPESE' -- non ci sono spese nella rata che vadano al veicolo
	, FORMAT(pre.TassoRiferimento, '0.0000', 'it-it') AS 'TASSO'
	, FORMAT((select sum(quotacapitale) from p2p_Rataprestito where IdPrestito = pre.id and P2P_RataPrestito.Stato = 10), '0.0000', 'it-it') AS 'CAPITALE RESIDUO' -- DA FINALIZZARE: Tutto il capitale residuo successivo alla presente rata, a prescindere dallo stato dei pagamenti precedenti
	, IIF(ra.importoresiduo = 0, FORMAT((select max(date) from P2P_RataPrestito_Pagamento where idprestito = pre.id and numerorata = ra.numerorata),'dd/MM/yyyy'), '') AS 'DATA PAGAMENTO' -- se la rata è completamente pagata, passiamo la data di scadenza della rata, altrimenti in campo è bianco
	, IIF(ra.importoresiduo = 0, FORMAT((select max(date) from P2P_RataPrestito_Pagamento where idprestito = pre.id and numerorata = ra.numerorata),'dd/MM/yyyy'), '') AS 'DATA VALUTA' -- come data pagamento
	--FORMAT(cp.data_pagamento,'dd/MM/yyyy') AS 'DATA PAGAMENTO' --data del saldo totale della rata (altrimenti passare il campo bianco)
	--, FORMAT(cp.data_pagamento,'dd/MM/yyyy') AS 'DATA VALUTA' -- come data pagamento
	, '' AS 'FLAG RATA IN MORA'
	, FORMAT(isnull(cs.capitale_residuo,0), '0.0000', 'it-it') AS 'CAPITALE SCADUTO (al netto di acconti)'
	, FORMAT(isnull(ins.interessi_residui,0), '0.0000', 'it-it') AS 'INTERESSI SCADUTI (al netto di acconti)'
	, '' AS 'INTERESSI DI MORA INIZIALI'
	, '' AS 'INTERESSI DI MORA PAGATI'
	, '' AS 'INTERESSI DI MORA MATURATI'
	, CAST(EOMONTH(GETDATE(),-1) AS DATE) AS 'DATA CONTABILE DI COMPETENZA'
	, FORMAT(GETDATE(),'dd/MM/yyyy') AS 'DATA ESTRAZIONE FISICA DEI DATI'

from VW_P2P_Prestito_Lender pre
	inner join P2P_Richiedente ric 
		on pre.IdRichiedente = ric.Id
	inner join P2P_RataPrestito ra 
		on pre.Id = ra.IdPrestito
	left join pagato_totalerata cp
		on pre.Id = cp.IdPrestito
	left join capitale_scaduto cs
		on pre.Id = cs.IdPrestito
	left join interessi_scaduti ins
		on pre.Id = ins.IdPrestito
where IdIstituzionale = @idistituzionale
	and pre.Stato not in (90, 91, 92, 93, 94, 95, 99) -- solo prestiti in vita
	and ra.Stato <> 0 -- escluse le rate inattive (es. per rinegoziazione piano ammortamento)
order by ra.IdPrestito, Ordine



