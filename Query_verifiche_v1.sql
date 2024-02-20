create procedure sp_EsitiVerifichePrestiti
as
	
select *
from
	(
	select
		pre.Id AS 'ID PRESTITO'
		, cast(pre.DataCreazione as date) as CreazionePrestito
		, finpr.Id_Pratica AS 'ID PRATICA'
		, stpr.StatusDescription AS 'STATO PRESTITO'
		, pre.Lender AS 'Lender'
		, tipfin.Descrizione AS 'Tipo Finanziamento'
		, CASE
				WHEN avv.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN avv.Checked = 0 THEN 'KO'
				WHEN avv.Checked = 1 AND avv.EsitoForzato = 0 THEN 'OK'
				WHEN avv.Checked = 1 AND avv.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Persone chiave e gruppo mappato e valutato'
		, CASE
				WHEN webrep.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN webrep.Checked = 0 THEN 'KO'
				WHEN webrep.Checked = 1 AND webrep.EsitoForzato = 0 THEN 'OK'
				WHEN webrep.Checked = 1 AND webrep.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Web Reputation'
		, CASE
				WHEN accmcc.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN accmcc.Checked = 0 THEN 'KO'
				WHEN accmcc.Checked = 1 AND accmcc.EsitoForzato = 0 THEN 'OK'
				WHEN accmcc.Checked = 1 AND accmcc.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Verificare accessibilità garanzia MCC'
		, CASE
				WHEN permcc.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN permcc.Checked = 0 THEN 'KO'
				WHEN permcc.Checked = 1 AND permcc.EsitoForzato = 0 THEN 'OK'
				WHEN permcc.Checked = 1 AND permcc.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Perimetro impresa unica Mcc'
		, CASE
				WHEN diff.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN diff.Checked = 0 THEN 'KO'
				WHEN diff.Checked = 1 AND diff.EsitoForzato = 0 THEN 'OK'
				WHEN diff.Checked = 1 AND diff.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'L''impresa non è classificata come impresa in difficoltà'
		, CASE
				WHEN ec.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN ec.Checked = 0 THEN 'KO'
				WHEN ec.Checked = 1 AND ec.EsitoForzato = 0 THEN 'OK'
				WHEN ec.Checked = 1 AND ec.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Estratto Conto da quadrare'
		, CASE
				WHEN CR.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN CR.Checked = 0 THEN 'KO'
				WHEN CR.Checked = 1 AND CR.EsitoForzato = 0 THEN 'OK'
				WHEN CR.Checked = 1 AND CR.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Analisi CR'
		, CASE
				WHEN coll.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN coll.Checked = 0 THEN 'KO'
				WHEN coll.Checked = 1 AND coll.EsitoForzato = 0 THEN 'OK'
				WHEN coll.Checked = 1 AND coll.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Analisi collegamenti'
		, CASE
				WHEN andam.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN andam.Checked = 0 THEN 'KO'
				WHEN andam.Checked = 1 AND andam.EsitoForzato = 0 THEN 'OK'
				WHEN andam.Checked = 1 AND andam.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Andamentale Estratti Conto'
		, CASE
				WHEN siccr.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN siccr.Checked = 0 THEN 'KO'
				WHEN siccr.Checked = 1 AND siccr.EsitoForzato = 0 THEN 'OK'
				WHEN siccr.Checked = 1 AND siccr.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS 'Validità report SIC e CR'
		, CASE
				WHEN geo.Checked is null THEN 'N/A' -- POA: VERIFICARE CON MAURIZIO
				WHEN geo.Checked = 0 THEN 'KO'
				WHEN geo.Checked = 1 AND geo.EsitoForzato = 0 THEN 'OK'
				WHEN geo.Checked = 1 AND geo.EsitoForzato = 1 THEN 'OK-'
				ELSE '' -- lasciamo bianco per i casi non previsti (non ce ne aspettiamo ad oggi)
		END AS  'Validazione telefonica e geografica delle sedi'
	from VW_P2P_Prestito_Lender pre
		inner join Finanziamenti_Pratiche finpr
			on pre.IdPraticaFinanziamento = finpr.Id_Pratica
				and pre.IdTipoFinanziamento not in (3,4,5,6,7,8,9,10) --Come da richieste del business
		/*inner join P2P_Richiedente ric
			on pre.IdRichiedente = ric.Id*/
		inner join STATI_PRESTITO stpr
			on pre.Stato = stpr.CodiceStato
		inner join P2P_Dom_TipologiaFinanziamento tipfin
			on pre.IdTipoFinanziamento = tipfin.Id
	-- Da qui in poi metto in join tutte le singole verifiche da vedere in un singolo record	
	
	
		left join AvvisiAdmin avv
			on avv.IdPraticaFin = finpr.Id_Pratica
				and avv.IdDominio = 13 /*Persone chiave e gruppo mappato e valutato*/
				and avv.Cestino = 0
		left join AvvisiAdmin webrep
			on webrep.IdPraticaFin = finpr.Id_Pratica
				and webrep.IdDominio = 22 /*Web Reputation*/
				and webrep.Cestino = 0
		left join AvvisiAdmin accmcc
			on accmcc.IdPraticaFin = finpr.Id_Pratica
				and accmcc.IdDominio = 1066 /*Verificare accessibilità garanzia MCC*/
				and accmcc.Cestino = 0
		left join AvvisiAdmin permcc
			on permcc.IdPraticaFin = finpr.Id_Pratica
				and permcc.IdDominio = 1068 /*Perimetro impresa unica Mcc*/
				and permcc.Cestino = 0
		left join AvvisiAdmin diff
			on diff.IdPraticaFin = finpr.Id_Pratica
				and diff.IdDominio = 1072 /*L'impresa non è classificata come impresa in difficoltà*/
				and diff.Cestino = 0
		left join AvvisiAdmin ec
			on ec.IdPraticaFin = finpr.Id_Pratica
				and ec.IdDominio = 7 /*Estratto Conto da quadrare*/
				and ec.Cestino = 0
		left join AvvisiAdmin CR
			on CR.IdPraticaFin = finpr.Id_Pratica
				and CR.IdDominio = 30 /*Analisi CR*/
				and CR.Cestino = 0
		left join AvvisiAdmin coll
			on coll.IdPraticaFin = finpr.Id_Pratica
				and coll.IdDominio = 1062 /*Analisi collegamenti*/
				and coll.Cestino = 0
		left join AvvisiAdmin andam
			on andam.IdPraticaFin = finpr.Id_Pratica
				and andam.IdDominio = 1064 /*Andamentale Estratti Conto*/
				and andam.Cestino = 0
		left join AvvisiAdmin siccr
			on siccr.IdPraticaFin = finpr.Id_Pratica
				and siccr.IdDominio = 1059 /*Validità report SIC e CR*/
				and siccr.Cestino = 0
		left join AvvisiAdmin geo
			on geo.IdPraticaFin = finpr.Id_Pratica
				and geo.IdDominio = 11 /*Validazione telefonica e geografica delle sedi*/
				and geo.Cestino = 0
	) tab
--where pre.Id = 1187

group by 
[ID PRESTITO]
, CreazionePrestito
, [ID PRATICA]
, [STATO PRESTITO]
, [Lender]
, [Tipo Finanziamento]
, [Persone chiave e gruppo mappato e valutato]
, [Web Reputation]
, [Verificare accessibilità garanzia MCC]
, [Perimetro impresa unica Mcc]
, [L'impresa non è classificata come impresa in difficoltà]
, [Estratto Conto da quadrare]
, [Analisi CR]
, [Analisi collegamenti]
, [Andamentale Estratti Conto]
, [Validità report SIC e CR]
, [Validazione telefonica e geografica delle sedi]
