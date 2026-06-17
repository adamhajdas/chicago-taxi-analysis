# 🚕 Chicago Taxi Analysis (BigQuery)

Projekt pokazuje jak z publicznego, nieidealnego datasetu taxi w Chicago (Google BigQuery) zbudowałem warstwę analityczną i wyciągnąłem praktyczne wnioski biznesowe.

Celem było pokazanie:
- warsztatu analitycznego
- pracy z nieidealnymi danymi
- świadomości kosztowej w BigQuery
- umiejętności budowy pipeline'u danych (base -> enriched -> silver -> marts)

---

## Architektura

1. **Data Ingestion**
   - kopiowanie danych do `trips_base`
   - partycjonowanie i klastrowanie (optymalizacja kosztów)

2. **Audyt jakości**
   - analiza NULLi
   - analiza payment_type
   - wykrywanie anomalii

3. **Warstwa enriched**
   - nowe metryki (km, czas, speed, $/km)
   - standaryzacja firm i płatności

4. **Warstwa silver**
   - usunięcie błędów i wartości odstających
   - deduplikacja
   - clean dataset do analizy

5. **Data marts**
   - czas (mart_time_analysis)
   - geografia (mart_geo_flows)
   - firmy (mart_company_performance)

---

## Co pokazuje projekt

- SQL (BigQuery / GoogleSQL)
- Data cleaning i walidacja
- Budowa warstw danych
- Myślenie biznesowe
- Praca z realnymi danymi

---

## Struktura

<img width="233" height="104" alt="image" src="https://github.com/user-attachments/assets/4e69cddd-10db-4ab2-b43f-9ca5ff0ef6f2" />
