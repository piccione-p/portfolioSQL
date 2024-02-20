
-- soc capitali
with ultimo_bilancio AS
(
select
	ROW_NUMBER() over (partition by pre.id order by [003_Anno_Riferimento] DESC) AS ordine
	, pre.Id AS prestitoriferimento -- il prestito di riferimento, per determinare l'ultimo bilancio depositato prima del congelamento MCC
	, bil.* -- tutto il bilancio core
	, isnull(bildett.[048_AI_Patrimonio_netto_capitale], '') AS [048_AI_Patrimonio_netto_capitale]-- elementi selezionati dal dettaglio
	, isnull(bildett.[077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo], 0) AS [077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo] -- elementi selezionati dal dettaglio
	, isnull(bildett.[049_AII_Patrimonio_netto_riserva_da_soprapprezzo_delle_azioni]
		+ bildett.[051_AIV_Patrimonio_netto_riserva_legale] 
		+ bildett.[052_AV_Patrimonio_netto_riserve_statutarie] 
		+ bildett.[053_AVI_Patrimonio_netto_riserva_per_azioni_proprie_in_portafoglio]
		+ bildett.[076_AVII_Patrimonio_netto_Altre_riserve_distintamente_indicate_totale_altre_riserve], 0) AS riserve -- RISERVE
from BilancioCore bil
	inner join BilancioDettaglio bildett
		on bil.[001_Id_Bilancio] = bildett.[001_Id_Bilancio]
			--and [003_Anno_Riferimento] < 2020 -- shitch x file totale / only 2020
	inner join P2P_Richiedente ric
		on bil.Id_PMI = ric.IdPmi
	inner join VW_P2P_Prestito_Lender pre
		on ric.id = pre.IdRichiedente 
			and DataErogazione is not null -- solo prestiti effettivamente erogati
			and IdIstituzionale <> 0 -- no retail (che comunque non hanno congelamento MCC)
--			and pre.Stato < 90 -- prestiti ancora in vita
	inner join Garanzie gar
		on pre.Id = gar.IdPrestito
	inner join Garanzie_Mcc mcc
		on mcc.IdGaranzia = gar.Id 
			and mcc.DataCongelamento is not null -- la garanzia deve essere stata congelata (va in coppia con idistituzionale)
			and CAST(mcc.DataCongelamento AS DATE) > CAST(bil.Data_Creazione AS DATE) -- esclude tutti i bilanci depositati dopo la data di congelamento. Nella where che segue, viene selezionato il bilancio più recente tra quelli rimasti
where bil.Depositato = 1 -- non bilancino, ma bilancio ufficiale
--order by pre.Id, ordine
--	and 
-- where CAST(Garanzie_Mcc.DataCongelamento as DATE) > 21 /*data di deposito bilancio*/
)

select
	ric.IdPmi AS IDPMI
	, pre.Id AS IdPrestito
	, ric.CodiceFiscale AS 'Codice Fiscale'
	, bil.[009_Dati_anagrafici_partita_iva] AS 'Partita IVA'
	, ric.Nome
	, bil.[003_Anno_Riferimento] AS 'Anno Ultimo Bilancio'
	, bil.[048_AI_Patrimonio_netto_capitale] AS 'Capitale Sociale'
	, bil.riserve AS Riserve
	, bil.[024_A_Totale_crediti_verso_soci_per_versamenti_ancora_dovuti] AS 'Crediti verso soci per versamenti ancora dovuti'
	, bil.[206_23_Utile_(perdita)_dell'esercizio] AS 'Risultato Esercizio'
	, iif([077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo]>=0, 0, [077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo]) AS 'Perdite A Nuovo'
	, iif([077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo]<=0, 0, [077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo]) AS 'Utili A Nuovo'
	, isnull(bil.[081_A_Totale_patrimonio_netto], '') AS 'Patrimonio Netto'
--	, pmi.Tipologia_Azienda
	--, mcc.DataCongelamento
from VW_P2P_Prestito_Lender pre
	inner join P2P_Richiedente ric
		on pre.IdRichiedente = ric.Id
--			and pre.Stato < 90 -- prestiti ancora in vita
			and pre.DataErogazione is not null
	inner join ultimo_bilancio bil
		on ric.IdPmi = bil.Id_PMI
			and bil.ordine = 1
			and bil.prestitoriferimento = pre.Id
--			and bil.[003_Anno_Riferimento] = 2020
			--and CAST(mcc.DataCongelamento AS DATE) > CAST(bil.Data_Creazione AS DATE) -- esclude tutti i bilanci depositati dopo la data di congelamento. Nella where che segue, viene selezionato il bilancio più recente tra quelli rimasti
	inner join PMI
		on PMI.Id_PMI = ric.IdPmi 
			and TRIM(pmi.Tipologia_Azienda) in ('SRL', 'SCPA', 'SAPA', 'SPA') -- solo società di capitali
where pre.DataErogazione is not null
	--and ordine = min(bil.ordine) 
--group by ric.IdPmi, pre.Id, ric.CodiceFiscale, bil.[009_Dati_anagrafici_partita_iva], ric.Nome--, bil.[003_Anno_Riferimento]--, mcc.DataCongelamento
order by IdPrestito


-- Bilanciocore -> depositato = 1 (non bilancino, ma bilancio vero)



--select top 100 * from BilancioDettaglio	   ;
--select top 100 * from BilancioCore		   ;

--select top 100 [048_AI_Patrimonio_netto_capitale] -- RS107 - patrimonio netto
--from BilancioDettaglio


--select [206_23_Utile_(perdita)_dell'esercizio] -- perdita / utile di esercizio
--from BilancioCore

--Capitale sociale (A1 SP passivo) - select 006_dati_anagrafici from BilancioDettaglio	
--Risultato d''esercizio (SP) - [206_23_Utile_(perdita)_dell'esercizio]
--Perdite portate a nuovo - [077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo]
--Utili portati a nuovo - [077_AVIII_Patrimonio_netto_utili_(perdite)_portati_a_nuovo]

