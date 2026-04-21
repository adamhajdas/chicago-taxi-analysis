# 🚕 Chicago Taxi Analysis (BigQuery)

Projekt pokazuje jak z publicznego, nieidealnego datasetu taxi w Chicago (Google BigQuery) zbudowałem warstwę analityczną i wyciągnąłem praktyczne wnioski biznesowe.

Celem było pokazanie:
- warsztatu analitycznego
- pracy z nieidealnymi danymi
- świadomości kosztowej w BigQuery
- umiejętności budowy pipeline'u danych (base → enriched → silver → marts)

---

## 🔧 Architektura

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
   - usunięcie błędów i outlierów
   - deduplikacja
   - clean dataset do analizy

5. **Data marts**
   - czas (mart_time_analysis)
   - geografia (mart_geo_flows)
   - firmy (mart_company_performance)

---

## 📊 Kluczowe wnioski

- 📈 Przejście z cash → card (2017–2021)
- ✈️ Kursy lotniskowe = segment premium (~4.5x droższe)
- 🕒 Najbardziej dochodowe godziny: 20:00–22:00
- 🌆 Centrum miasta generuje największy wolumen
- ⚠️ Dane 2022–2023 są niepełne i nie nadają się do analizy trendów

---

## 🧠 Co pokazuje projekt

- SQL (BigQuery / GoogleSQL)
- Data cleaning i walidacja
- Budowa warstw danych
- Myślenie biznesowe
- Praca z realnymi danymi

---

## 📁 Struktura

sql/
├── 01_ingestion_and_audit.sql
├── 02_enriched_and_silver.sql
└── 03_marts_and_reports.sql
