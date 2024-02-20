
select -- al fine di escludere le società che hanno cambiato tipo di contabilità durante la vita del prestito
	ROW_NUMBER() over (partition by prestitoriferimento order by [Anno_Riferimento] DESC) AS ordine
	, prestitoriferimento -- il prestito di riferimento, per determinare l'ultimo bilancio depositato prima del congelamento MCC
	, Anno_Riferimento
	, RS107_PatrimonioNetto
	, UtileEsercizio
	, PerditaEsercizio
	, TipoContabilità
into #datibilanci
from 
-- società persone contabilità ordinaria
	(select
		ROW_NUMBER() over (partition by pre.id order by [Anno_Riferimento] DESC) AS ordine
		, pre.Id AS prestitoriferimento -- il prestito di riferimento, per determinare l'ultimo bilancio depositato prima del congelamento MCC
		, bil.Anno_Riferimento
		, bil.RF66_Patrimonio_netto AS RS107_PatrimonioNetto
		, iif(CAST(bil.RF4_Utile AS MONEY)>=0, bil.RF4_Utile, 0) AS UtileEsercizio
		, iif(CAST(bil.RF4_Utile AS MONEY)<=0, ABS(bil.RF4_Utile), 0) AS PerditaEsercizio
		, 'Ordinaria' AS TipoContabilità
	from BilancioUnicoSP_Ord bil
		inner join BilancioDettaglio bildett
			on bil.Id_Bilancio = bildett.[001_Id_Bilancio]
			--	and bil.Anno_Riferimento < 2020 -- shitch x file totale / only 2020
		inner join P2P_Richiedente ric
			on bil.Id_PMI = ric.IdPmi
		inner join VW_P2P_Prestito_Lender pre
			on ric.id = pre.IdRichiedente 
				and DataErogazione is not null -- solo prestiti effettivamente erogati
				and IdIstituzionale <> 0 -- no retail (che comunque non hanno congelamento MCC)
				and pre.Stato < 90 -- prestiti ancora in vita
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

	UNION
	-- società persone contabilità semplificata
	select
		ROW_NUMBER() over (partition by pre.id order by [Anno_Riferimento] DESC) AS ordine
		, pre.Id AS prestitoriferimento -- il prestito di riferimento, per determinare l'ultimo bilancio depositato prima del congelamento MCC
		, bil.Anno_Riferimento
		, '' AS RS_107_PatrimonioNetto
		, iif(RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi>=0, RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi, 0) AS UtileEsercizio
		, iif(RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi<=0, ABS(RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi), 0) AS PerditaEsercizio
		, 'Semplificata' AS TipoContabilità
	from BilancioUnicoSP_Sem bil
	--	inner join BilancioDettaglio bildett /*non previsto per la contabilità semplificata*/
	--		on bil.Id_Bilancio = bildett.[001_Id_Bilancio]

		inner join P2P_Richiedente ric
			on bil.Id_PMI = ric.IdPmi
		inner join VW_P2P_Prestito_Lender pre
			on ric.id = pre.IdRichiedente 
				and DataErogazione is not null -- solo prestiti effettivamente erogati
				and IdIstituzionale <> 0 -- no retail (che comunque non hanno congelamento MCC)
				and pre.Stato < 90 -- prestiti ancora in vita
		inner join Garanzie gar
			on pre.Id = gar.IdPrestito
		inner join Garanzie_Mcc mcc
			on mcc.IdGaranzia = gar.Id 
				and mcc.DataCongelamento is not null -- la garanzia deve essere stata congelata (va in coppia con idistituzionale)
				and CAST(mcc.DataCongelamento AS DATE) > CAST(bil.Data_Creazione AS DATE) -- esclude tutti i bilanci depositati dopo la data di congelamento. Nella where che segue, viene selezionato il bilancio più recente tra quelli rimasti
	where bil.Depositato = 1 -- non bilancino, ma bilancio ufficiale
		--and bil.Anno_Riferimento < 2020 -- shitch x file totale / only 2020

	UNION
	-- persone contabilità ordinaria
	select
		ROW_NUMBER() over (partition by pre.id order by [Anno_Riferimento] DESC) AS ordine
		, pre.Id AS prestitoriferimento -- il prestito di riferimento, per determinare l'ultimo bilancio depositato prima del congelamento MCC
		, bil.Anno_Riferimento
		, '' AS RS_107_PatrimonioNetto
		, iif(bil.RF2_Utile_risultante_dal_conto_economico>=0, bil.RF2_Utile_risultante_dal_conto_economico, 0) AS UtileEsercizio
		, iif(bil.RF2_Utile_risultante_dal_conto_economico<=0, ABS(bil.RF2_Utile_risultante_dal_conto_economico), 0) AS PerditaEsercizio
		, 'Ordinaria' AS TipoContabilità
	from BilancioUnicoPF_Ord bil
	--	inner join BilancioDettaglio bildett /*non previsto per la contabilità semplificata*/
	--		on bil.Id_Bilancio = bildett.[001_Id_Bilancio]
		inner join P2P_Richiedente ric
			on bil.Id_PMI = ric.IdPmi
		inner join VW_P2P_Prestito_Lender pre
			on ric.id = pre.IdRichiedente 
				and DataErogazione is not null -- solo prestiti effettivamente erogati
				and IdIstituzionale <> 0 -- no retail (che comunque non hanno congelamento MCC)
				and pre.Stato < 90 -- prestiti ancora in vita
		inner join Garanzie gar
			on pre.Id = gar.IdPrestito
		inner join Garanzie_Mcc mcc
			on mcc.IdGaranzia = gar.Id 
				and mcc.DataCongelamento is not null -- la garanzia deve essere stata congelata (va in coppia con idistituzionale)
				and CAST(mcc.DataCongelamento AS DATE) > CAST(bil.Data_Creazione AS DATE) -- esclude tutti i bilanci depositati dopo la data di congelamento. Nella where che segue, viene selezionato il bilancio più recente tra quelli rimasti
	where bil.Depositato = 1 -- non bilancino, ma bilancio ufficiale
		--and bil.Anno_Riferimento < 2020 -- shitch x file totale / only 2020

	UNION
	--  persone contabilità semplificata
	select
		ROW_NUMBER() over (partition by pre.id order by [Anno_Riferimento] DESC) AS ordine
		, pre.Id AS prestitoriferimento -- il prestito di riferimento, per determinare l'ultimo bilancio depositato prima del congelamento MCC
		, bil.Anno_Riferimento
		, '' AS RS_107_PatrimonioNetto
		, iif(RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi>=0, RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi, 0) AS UtileEsercizio
		, iif(RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi<=0, ABS(RG12_TotaleComponentiPositivi-RG24_TotaleComponentiNegativi), 0) AS PerditaEsercizio
		, 'Semplificata' AS TipoContabilità
	from BilancioUnicoPF_Sem bil
	--	inner join BilancioDettaglio bildett /*non previsto per la contabilità semplificata*/
	--		on bil.Id_Bilancio = bildett.[001_Id_Bilancio]
		inner join P2P_Richiedente ric
			on bil.Id_PMI = ric.IdPmi
		inner join VW_P2P_Prestito_Lender pre
			on ric.id = pre.IdRichiedente 
				and DataErogazione is not null -- solo prestiti effettivamente erogati
				and IdIstituzionale <> 0 -- no retail (che comunque non hanno congelamento MCC)
				and pre.Stato < 90 -- prestiti ancora in vita
		inner join Garanzie gar
			on pre.Id = gar.IdPrestito
		inner join Garanzie_Mcc mcc
			on mcc.IdGaranzia = gar.Id 
				and mcc.DataCongelamento is not null -- la garanzia deve essere stata congelata (va in coppia con idistituzionale)
				and CAST(mcc.DataCongelamento AS DATE) > CAST(bil.Data_Creazione AS DATE) -- esclude tutti i bilanci depositati dopo la data di congelamento. Nella where che segue, viene selezionato il bilancio più recente tra quelli rimasti
	where bil.Depositato = 1 -- non bilancino, ma bilancio ufficiale
		--and bil.Anno_Riferimento < 2020 -- shitch x file totale / only 2020
	) tab


select
	ric.IdPmi AS IDPMI
	, pre.Id AS IdPrestito
	, PMI.Codice_Fiscale
	, PMI.Partita_IVA AS Partita_IVA
	, PMI.Denominazione_Sociale
	, bil.Anno_Riferimento AS [anno_ultimo_mod.unico]
	, bil.RS107_PatrimonioNetto AS RS107_PatrimonioNetto
	, bil.UtileEsercizio AS UtileEsercizio
	, -ABS(bil.PerditaEsercizio) AS PerditaEsercizio
	, pmi.Tipo_Contabilita AS TipoContabilità
--	, pmi.Tipologia_Azienda
	--, mcc.DataCongelamento
from VW_P2P_Prestito_Lender pre
	inner join P2P_Richiedente ric
		on pre.IdRichiedente = ric.Id
			and pre.Stato < 90 -- prestiti ancora in vita
			and pre.DataErogazione is not null
	--inner join ultimo_bilancio bil
	--	on ric.IdPmi = bil.Id_PMI
	--		and bil.ordine = 1
	--		and bil.prestitoriferimento = pre.Id
			--and CAST(mcc.DataCongelamento AS DATE) > CAST(bil.Data_Creazione AS DATE) -- esclude tutti i bilanci depositati dopo la data di congelamento. Nella where che segue, viene selezionato il bilancio più recente tra quelli rimasti
	inner join PMI
		on PMI.Id_PMI = ric.IdPmi 
			and TRIM(pmi.Tipologia_Azienda) not in ('SRL', 'SCPA', 'SAPA', 'SPA')
	inner join #datibilanci bil
		on pre.id = bil.prestitoriferimento
			and bil.ordine = 1
			and PMI.Id_PMI = ric.IdPmi
--			and bil.Anno_Riferimento = 2020 -- per estrarre solo società il cui ultimo bilancio è riferito al 2020
where pre.DataErogazione is not null
	--and ordine = min(bil.ordine) 
--group by ric.IdPmi, pre.Id, ric.CodiceFiscale, bil.[009_Dati_anagrafici_partita_iva], ric.Nome--, bil.[003_Anno_Riferimento]--, mcc.DataCongelamento
order by IdPrestito


drop table #datibilanci
