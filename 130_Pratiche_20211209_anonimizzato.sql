DECLARE @idistituzionale int = 5091;


WITH 

---- 0. Perimetro della estrazione Ifrit (-> spostato nella from generale: da rivalutare)
--perimetro AS
--(
--select 
--	IdPrestatore
--from
--	P2P_Prestatore_ProfiloIstituzionale
--where IdPrestatore = 5091 -- Ifrit Spv
--)

---- 1. individuazione prima rata non saldata completamente in prestiti non defaultati, liquidati o protetti
--, 
prima_non_saldata AS 
(
select *
from
	(select 
	ra.*
	, ROW_NUMBER() OVER (partition by idprestito order by ordine) first_nopayment
	,pre.stato stato_prestito
	from P2P_RataPrestito ra
		inner join P2P_Prestito pre on ra.IdPrestito = pre.Id and pre.Stato not in (94,93,92)
	where ra.Stato in (12,15)) tab
where first_nopayment = 1
and IdPrestito not in (1060)) -- verificare con Maurizio, sembra trattarsi di un caso di errata imputazione dell'incasso. Da rimuovere dopo gennaio '22

-- 2. individuazione ultimo pagamento x prestito
, ultimo_pagamento AS 
(
select *
from 
	(SELECT
		id
		, date
		, IdPrestito
		, ROW_NUMBER() over (partition by idprestito order by date desc) last_payment
	from 
		P2P_RataPrestito_Pagamento
	--order by date desc
	) tab
where last_payment = 1)

-- 3. matching 1+2 - giorni di scaduto continuativo
, scaduto_continuativo AS
(
select
	np.IdPrestito
	,np.stato_prestito
	, DATEDIFF(day, lp.[Date], getdate()) days_since_last_payment -- per i prestiti che non hanno mai pagato, aggiungere conteggio dal giorno di scadenza della rata, non dall'ultimo pagamento
	--,*
from 
	prima_non_saldata np
		left join ultimo_pagamento lp 
			on np.IdPrestito = lp.IdPrestito
--order by days_since_last_payment asc
)

--4. durata originaria del fido
, durata_fido AS
(
select
	id idprestito
	, Durata+isnull(Durata_Preammortamento_Finanziario,0) durata_totale
--into #durataoriginariafido
from 
	P2P_Prestito
--order by Id
)

-- 5. ultima rata piano di ammortamento
, ultima_rata_ammortamento AS
(
select 
	IdPrestito
	, max(scadenza) ultima_rata
from 
	P2P_RataPrestito
where Stato <> 0
group by IdPrestito
--order by IdPrestito
)

-- 5.5. chiusura rapporto - data ultima varazione in chiuso
, chiusura_rapporto AS
(
select 
	IdPrestito
	, min(DataVariazione) as DataVariazione 
from 
	P2P_PrestitoStoricoStati 
where 
	CodiceStato in (90,91, 92, 93, 94) 
group by idprestito
)

-- 6. data della prima rata non pagata di un prestito (rata stato 12,15)
, prima_rata_nonpagata AS
(
select 
idprestito
, min(Scadenza) prima_rata_nonpagata
from
	P2P_RataPrestito
where Stato in (12,15)
group by IdPrestito
)

-- 7. calcolo ultima data cessione
, data_cessione AS
(
select 
	IdPrestito
	, max(DataCessione) data_cessione_ultima
from 
	P2P_RichiesteCessioneCrediti
where EsitoCessione = 'OK' and idprestatoreacquirente = @idistituzionale
group by IdPrestito
)

-- 8. presenza concessioni
, concessioni AS
(
select
	distinct IdPrestito
from 
	P2P_RataPrestito
where IdEccezionePiano is not null
)

-- 9. saldo creditore a data valutazione (= data cessione): usato anche per prezzo cessione
, saldo_data_valutazione AS
(
select
	*
	--idprestito
	--, IdPrestatore
	--, ImportoResiduo
	--, DataCreazione
from 
	P2P_Investimento
where Codice_Stato = 20
)

-- 10. saldo creditore attuale
, saldo_attuale AS
(
select
	idprestito
	, IdPrestatore
	, ImportoResiduo
	, DataCreazione
from 
	P2P_Investimento
where Codice_Stato = 30
)

-- 11. Numero totale di concessioni sul prestito
, totale_eccezioni AS
(
select
	IdPrestito
	,count(idprestito) numero_eccezioni
from 
	P2P_Prestito_EccezionePianoRate
group by IdPrestito
)

-- 12. Esistenza garanzia
, garanzia_esistente AS
(
select
	IdPrestito
from
	Garanzie
where stato <>0  -- No garanzie in stato "inattivo"
	and DataScadenza > GETDATE() -- no garanzie con data di scadenza nel passato (i.e. scadute)
group by IdPrestito
)

--estrazione flusso (rif. end of month precedente)
--da lanciare su DB di copia di fine mese

SELECT
	'RPT' AS 'TIPO'
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
	, 2921 AS 'SCHEDA'
	, '' AS 'CODICE CONTRATTO'
	, pre.id AS 'CODICE PRATICA 130 SERVICING'
	, pre.id AS 'CODICE ID RAPPORTO ORIGINALE'
	, format(ric.IdPmi,'0100000000000000') AS 'NDG DEBITORE 130 SERVICING' -- da recuperare tabella di origine del dato
	, format(ric.IdPmi,'0100000000000000') AS 'NDG ORIGINARIO DEL DEBITORE' -- da recuperare tabella di origine del dato
	, ric.Nome AS 'NOMINATIVO DEBITORE'
	, '45940660' AS 'CODICE CR CEDENTE ORIGINARIO 3S'
	, '45940660' AS 'CODICE CR ORIGINATOR VE'
	, CASE
					when tipfin.id in (2,7,9,11,12) then '001' -- Finanziamento rateale a medio/lungo termine 
					else '903' -- Finanziamento rateale a breve termine - fino 1 anno 
		end AS 'FORMA TECNICA 130 SERVICING'
	, '339' AS 'FINALITA'' DEL CREDITO'
	, CASE 
					WHEN gar.IdPrestito is null THEN '0' --Se non è presente un record nella join, non c'è una garanzia attiva (cfr. with 12)
					ELSE '1'
		END AS 'CREDITO GARANTITO'
	, FORMAT(EOMONTH(GETDATE(),-1), 'dd/MM/yyyy') AS 'DATA CONTABILE DI COMPETENZA'
	, '' AS 'DATA DI VALUTAZIONE DEL CREDITO'
	, ISNULL(FORMAT(sdv.ImportoResiduo, '#############.00', 'it-it'), '') AS 'SALDO CREDITORE (GBV) ALLA DATA VALUTAZIONE'
	, ISNULL(FORMAT(round(sdv.ImportoResiduo - pre.SpeseIniziali + ((fees.commissioneservizipagamento + fees.commissioneserviziaccessori + monthlyplatformfees + monthlyspecialservicerfees)*sdv.ImportoResiduo),2), '#############.00', 'it-it'), '') AS 'PREZZO DI CESSIONE'
	, isnull(format(cess.data_cessione_ultima,'dd/MM/yyyy'), '') AS 'DATA DI CESSIONE'
	, ISNULL(FORMAT(round(sdv.ImportoResiduo - (sdv.ImportoResiduo - pre.SpeseIniziali + ((fees.commissioneservizipagamento + fees.commissioneserviziaccessori + monthlyplatformfees + monthlyspecialservicerfees)*sdv.Importoresiduo)),2), '#############.00', 'it-it'), '') AS 'PERDITE DA CESSIONE'
	, isnull(format(cess.data_cessione_ultima,'dd/MM/yyyy'), '') AS 'DATA DI EFFICACIA ECONOMICA'
	, '' AS 'CODICE LEGALE'
	, CASE
					WHEN pre.stato in (90,91, 92, 93, 94) THEN 'C'
					ELSE 'A'
		END AS 'POSIZIONE APERTA O CHIUSA'
	, IIF(pre.stato in (90, 91, 92, 93, 94), FORMAT(chius.datavariazione,'dd/MM/yyyy'), '') AS 'DATA CHIUSURA' --select IdPrestito, min(DataVariazione) as DataVariazione from P2P_PrestitoStoricoStati where CodiceStato in (90,91, 92, 93, 94) group by idprestito
	, CASE
					WHEN pre.Stato = 90 THEN '01' -- estinzione ordinaria
					WHEN pre.Stato = 91 THEN '03' -- estinzione anticipata
					WHEN pre.Stato = 92 THEN '06' -- liquidazione garanzie
					WHEN pre.Stato = 93 THEN '04' -- liquidazione garanzie
					WHEN pre.Stato = 94 THEN '06' -- liquidazione garanzie
					ELSE ''
		END AS 'MOTIVAZIONE CHIUSURA'
	, '1' AS 'RESIDENZA E DIVISA' -- residente (in Italia) e euro
	, '242' AS 'CODICE DIVISA' -- valuta €
	, '8' AS 'IMPORT/EXPORT' -- finalità del credito "altro"
	, '0' AS 'CONTESTAZIONE CREDITO' -- non contestato
	, IIF(eomonth(cess.data_cessione_ultima) = eomonth(pre.DataErogazione), 0, 1)AS 'SEGNALAZIONE IN CR' -- Se la cessione avviene nello stesso mese di erogazione, la contribuzione non viene fatta da noi ("0")
	, CASE
					WHEN pre.stato in (50, 60)	THEN '3'
					WHEN pre.stato in (70)		THEN '5'
					WHEN pre.stato in (80)		THEN '9'
					ELSE ''
		END AS 'CODICE CLASSIFICAZIONE' 
	, format(pre.Datacreazione,'dd/MM/yyyy') AS 'DATA DELIBERA'
	, format(pre.Importo, '#############.00', 'it-it') AS 'IMPORTO DELIBERATO'
	, '1' AS 'STATO DEL CONTRATTO' -- "deliberato e stipulato", non cediamo contratti da stipulare
	, '0' AS 'STATO ATTUALE DI CONTESTAZIONE CREDITO'
	, format(pre.DataErogazione,'dd/MM/yyyy') AS 'DATA STIPULA'
	, format(pre.DataErogazione,'dd/MM/yyyy') AS 'DATA EROGAZIONE'
	, format(pre.Importo, '#############.00', 'it-it') AS 'IMPORTO EROGATO' --SMARCATO: importo finanziato
	, format(pre.DataErogazione,'dd/MM/yyyy') AS 'DATA INIZIO RAPPORTO'
	, IIF(pre.Stato in (90, 91, 92, 93, 94), format(chius.datavariazione,'dd/MM/yyyy'), format(amm.ultima_rata,'dd/MM/yyyy')) AS 'DATA SCADENZA RAPPORTO' -- DA FINALIZZARE: SE APERTO OK, SE CHIUSO PRENDERE DA STORICO
	, format(amm.ultima_rata,'dd/MM/yyyy') AS 'ULTIMO TERMINE DI PAGAMENTO'
	, fid.durata_totale AS 'DURATA ORIGINARIA FIDO'
	, isnull(FORMAT(nop.prima_rata_nonpagata,'dd/MM/yyyy'), '') AS 'DATA PRIMA RATA SCADUTA'
	, isnull(sc.days_since_last_payment, '') AS 'GIORNI DI SCADUTO CONTINUATIVO'
	, '' AS 'QUOTE CAPITALE DI RATE/CANONI A SCADERE'
	, '' AS 'QUOTE CAPITALE DI RATE/CANONI SCADUTI NON IN MORA'
	, '' AS 'QUOTE CAPITALE DI RATE/CANONI SCADUTI IN MORA'
	, '' AS 'PREZZO DI RISCATTO BENE IN LEASING'
	, '' AS 'SALDO A DEBITO SU C/C'
	, '' AS 'VALORE NOMINALE FATTURE O EFFETTI'
	, '' AS 'INTERESSI IN MORA'
	, '' AS 'INTERESSI NON IN MORA'
	, '' AS 'TASSO DI MORA'
	, '' AS 'MORA MATURATA'
	, '' AS 'SPESE ACCESSORIE: IVA'
	, '' AS 'SPESE ACCESSORIE: COMMISSIONI'
	, '' AS 'SPESE ACCESSORIE: ALTRE SPESE'
	, '' AS 'ONERI DI PRELOCAZIONE'
	, '' AS 'ALTRI ONERI'
	, '' AS 'RATEI E RISCONTI'
	, '' AS 'IMPORTI ANTICIPATI: CAPITALE'
	, '' AS 'IMPORTI ANTICIPATI: SPESE'
	, ISNULL(FORMAT(sa.ImportoResiduo, '#############.00', 'it-it'), '') AS 'SALDO CREDITORE (GBV) ATTUALE'
	, '0' AS 'OPERAZIONE IN POOL' --non eseguiamo operazioni in pool
	, '0' AS 'PERCENTUALE PARTECIPAZIONE POOL' --non eseguiamo operazioni in pool
	, IIF(conc.IdPrestito is not null, 2, 0) AS 'OGGETTO DI CONCESSIONI' -- se esistono rate con eccezioni al piano, allora esistono concessioni con prestito ancora performing. Non usato il codice per crediti non performing
	, ISNULL(ecc.numero_eccezioni,'') AS 'NUMERO CONCESSIONI' -- 
	, '0' AS 'FINANZIAMENTO PROCEDIMENTO PREVENZIONE ANTIMAFIA O SOGGETTO USURA'
	, '0' AS 'DOMANDA DI CONCORDATO PREVENTIVO "IN BIANCO" O CON CONTINUITA'' AZIENDALE'
	, '' AS 'DATA INIZIO PROCEDIMENTO'
	, '' AS 'DATA FINE PROCEDIMENTO'
	, format(getdate(),'dd/MM/yyyy') AS 'DATA ESTRAZIONE FISICA DEI DATI'

from VW_P2P_Prestito_Lender pre --P2P_Prestito
	inner join P2P_Richiedente ric 
		on pre.IdRichiedente = ric.Id and pre.IdIstituzionale = @idistituzionale
	inner join P2P_RichiesteCessioneCrediti c 
		on pre.id = c.IdPrestito and c.IdPrestatoreAcquirente = @idistituzionale
	inner join garanzia_esistente gar
		on pre.id = gar.IdPrestito
	--left join Garanzie_Mcc mcc 
	--	on gar.Id = mcc.IdGaranzia
	left join data_cessione cess
		on pre.Id = cess.IdPrestito
	left join P2P_Dom_TipologiaFinanziamento tipfin 
		on pre.idtipofinanziamento = tipfin.id
	left join scaduto_continuativo sc
		on pre.id = sc.idprestito
	left join durata_fido fid
		on pre.id = fid.idprestito
	left join ultima_rata_ammortamento amm
		on pre.id = amm.idprestito
	left join chiusura_rapporto chius
		on pre.Id = chius.IdPrestito
	left join prima_rata_nonpagata nop
		on pre.id = nop.idprestito
	left join concessioni conc
		on pre.Id = conc.IdPrestito
	left join saldo_data_valutazione sdv
		on pre.Id = sdv.IdPrestito
	left join saldo_attuale sa
		on pre.Id = sa.IdPrestito
	left join totale_eccezioni ecc
		on pre.Id = ecc.IdPrestito
	inner join Dominio_Fees_Cartolarizzazioni fees -- join come nella relativa query BOS
		on fees.durata_ammortamento = pre.Durata 
			and fees.durata_preammortamento = (pre.Durata_Preammortamento_Finanziario+1)
			and fees.IdPrestatoreIstituzionale = c.IdPrestatore
where idistituzionale = @idistituzionale
	AND 
	(
		(pre.dataerogazione is not null and pre.Stato not in (90, 91, 92, 93, 94, 99)) -- escludere i prestiti non ancora erogati e gli stato 99
		OR (pre.Stato in (90, 91, 92, 93, 94) and eomonth(chius.DataVariazione) = EOMONTH(GETDATE(),-1)) -- inclusi i chiusi nell'ultimo mese
	)
