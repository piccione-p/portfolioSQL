-- verificare a mano a quale SPV si riferiscono gli eventuali storni interessi

DECLARE @datafine date = '2022-02-28'; -- ultimo giorno del mese di riferimento
DECLARE @datainizio date = dateadd(day,1,eomonth((dateadd(month, -1, @datafine))));-- viene calcolato in automatico l'inizio del mese di riferimento

/*DECLARE @datainizio DATE = '2022-02-01'; --inserire il primo giorno del mese di riferimento
DECLARE @datafine DATE = '2022-02-28'; -- inserire l'ultimo giorno del mese di riferimento
DECLARE @idprestatore int = ####; --inserire l'id del lender di riferimento*/

with prestiti_rate_annullate AS -- individua prestiti e rate relative, che hanno subito annulllamento dopo essere state in ritardo
(
select rat.IdPrestito, rat.Id, intp.interessi_pagati
from P2P_RataPrestitoStoricoStati ss
	inner join P2P_RataPrestito rat
		on ss.IdRataPrestito = rat.Id
			and ss.CodiceStato = 12
			and rat.Stato = 0
	left join( --non deve essere stornata la quota interessi eventualmente pagata in parte 
				select 
				idprestito
				, NumeroRata
				, sum(QuotaInteressiPagata) AS interessi_pagati
				from P2P_RataPrestito_Pagamento
				group by IdPrestito, NumeroRata) intp
		on rat.IdPrestito = intp.IdPrestito
			and rat.NumeroRata = intp.NumeroRata
)
select *
into #storni
from
(
	select 
		rat.id AS Idrata
		, 0 AS InteressiPagati
		, 0 AS CapitalePagato
		, 0 AS InteressiDovuti
		, rat.QuotaInteressi-isnull(ann.interessi_pagati,0) AS InteressiStornati -- colonna da aggiungere nella estrazione del flusso
		, rat.Scadenza AS [date] -- data in cui doveva essere pagata la rata
		, rat.IdPrestito
		, rat.NumeroRata
		, CAST(pecc.DataApplicazioneUtc AS DATE) AS DataValuta
		, pre.IdRichiedente
	from P2P_RataPrestito rat
		--inner join P2P_Prestito_EccezionePianoRate ecc -- eccezioni all'originale piano rate /*tabella dismessa*/
			--on rat.IdPrestito = ecc.IdPrestito /*ecc. - tabella dismessa*/
		inner join prestiti_rate_annullate ann --i prestiti e le relative rate che sono state annullate dopo essere state in ritardo
			on rat.IdPrestito = ann.IdPrestito
				and rat.Id = ann.Id
		inner join VW_P2P_Prestito_Lender pre -- per recuperare il lender
			on pre.Id = rat.IdPrestito 
				/*and pre.idistituzionale = @idprestatore*/
				and pre.Stato not in (90,91,92,93/* - liquidato, è da tenere?*/,94,95,99)
		inner join P2P_Prestatore_ProfiloIstituzionale ist
			on pre.IdIstituzionale = ist.IdPrestatore
		left join P2P_Prestito_PropostaEccezionePianoRate pecc -- per recuperare le date di inizio validità del nuovo piano e quindi estrarre i dati nel mese di riferimento
			on pecc.IdPrestito = rat.IdPrestito
				and pecc.Cestino = 0
				--and pecc.IdTipoEccezione = ecc.IdTipoEccezione /*ecc. - tabella dismessa*/
	where ist.IdTipologia = 2 /*in (4731/*Auxilio*/, 4990/*Galadriel*/, 4997/*Kripton*/, 5091/*Ifrit*/)*/ -- solo i prestiti delle SPV
		and pecc.DataApplicazioneUtc between @datainizio and @datafine -- la validità del nuovodeve essere iniziare all'interno del mese di riferimento
--	order by rat.IdPrestito, rat.Ordine
) tab

select 
	/*st.idrata -- per rintracciare di quale rata si sta parlando: scommentare
	,*/'174' AS 'SOCIETA'
	, '1855' AS 'PORTAFOGLIO'
	, IdPrestito AS 'CODICE PRATICA "130 SERVICING"'
	, format(ric.IdPmi,'0100000000000000') AS 'NDG DEBITORE "130 SERVICING"'
	, upper(ric.Nome) AS 'NOMINATIVO DEBITORE'
	, 136 AS 'CAUSALE MOVIMENTO'
	, 'Storno imputato a interessi' AS 'DESCRIZIONE CAUSALE MOVIMENTO'
	, st.InteressiStornati AS 'IMPORTO'
	, '-' AS 'SEGNO'
	, format(st.datavaluta,'dd/MM/yyyy') AS 'DATA VALUTA'
	, '' AS 'DATA INCASSO'
	, format(getdate(),'dd/MM/yyyy') AS 'DATA ESTRAZIONE FISICA DEI DATI'
from #storni st
	left join P2P_Richiedente ric
		on st.IdRichiedente = ric.Id
where Idrata < (select max(Idrata) from #storni)

drop table #storni