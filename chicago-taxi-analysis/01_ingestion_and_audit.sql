# ========================================================================================================================
# Wstęp - Taxi Chicago Portfolio
# ========================================================================================================================

/*
  Projekt pokazuje jak z publicznego, nieidealnego datasetu taxi w Chicago z Google Cloud Platform zbudowałem sensowną warstwę analityczną 
  i wyciągnąłem praktyczne wnioski o popycie, geograficznych hotspotach, płatnościach i zmianach rynku.
  Chciałbym zaprezentować za jego pomocą warsztat analityczny i świadomość biznesowoą oraz pokazać biegłość w środowisku chmurowym (Google Cloud Platform / BigQuery) 
  oraz umiejętność szybkiej adaptacji do specyficznych dialektów SQL (GoogleSQL).

  Źródło
  Na początek dane źródłowe przeniosłem do własnej tabeli trips_base, z partycjonowaniem i klastrami, żeby ograniczyć ilość skanowanych danych.
    ↓
  Warstwa enriched - Audyt jakości
  Przygotowałem rozbudowany widok do dalszej pracy. Audyt dotyczył m.in. kompletności danych (nulle), spójności w nazwach firm, metodach płatności, anomalii logicznych.
    ↓
  Warstwa silver (cleaned)
  Stworzyłem oczyszczoną tabelę wzbogaconą o dodatkowe informacje. Zależało mi na pozbyciu się śmieciowych rekordów, żeby nic nie zaburzało dalszej analizy.
    ↓
  MARTS (agregacje, metryki biznesowe)
  Przygotowałem 3 data marty ułatwiające dalszą analizę: czasową (mart_time_analysis), przestrzenną (mart_geo_flows) i wydajności firm (mart_company_performance). 
  Zależało mi na zmniejszeniu zużycia transferu.
    ↓
  Raporty i wnioski
  Do każdego data mart'u przygotowałem kilka raportów z KPI, z których można wyciągać realne wnioski o branży.
*/

# ============================================================
# Odczyt surowych danych
# ============================================================

CREATE OR REPLACE TABLE `taxi-chicago-portfolio.taxi_data.trips_base`
PARTITION BY partition_month                                              -- partycjonowanie
CLUSTER BY company, taxi_id, pickup_community_area, payment_type          -- klastry
OPTIONS (
  require_partition_filter = TRUE                                         -- zabezpieczam zużycie transferu na wypadek nieuważnego uruchomienia bez filtra na daty
)
AS
SELECT
  DATE_TRUNC(DATE(trip_start_timestamp), MONTH)           AS partition_month,
  t.*
FROM `bigquery-public-data.chicago_taxi_trips.taxi_trips` AS t
WHERE trip_start_timestamp IS NOT NULL;

/*
  Zamiast pracować na widoku publicznym, skopiowałem dane do własnej tabeli z partycjonowaniem. To od razu pozwoliło zredukować ilość skanowanych danych 
  we wszystkich dalszych działaniach.
*/

# ************************************************************************************************************************
# ========================================================================================================================
# AUDYT JAKOŚCI DATASET TAXI CHICAGO
# ========================================================================================================================
# ************************************************************************************************************************

# ============================================================
# Kompletność danych, NULLe
# ============================================================

WITH count_of_nulls AS (
  SELECT
      EXTRACT(YEAR FROM trip_start_timestamp)       AS year
    --, EXTRACT(MONTH FROM trip_start_timestamp)      AS month             -- zakomentowane części pod analizę lat 2022 i 2023
    --, COUNT(DISTINCT DATE(trip_start_timestamp))    AS distinct_days     -- zliczam ile dni miesiąca jest uwzględnione
    , COUNT(*)                                      AS total_rows
    , COUNTIF(trip_end_timestamp IS NULL)           AS null_trip_end_timestamp
    , COUNTIF(trip_seconds IS NULL)                 AS null_trip_seconds
    , COUNTIF(trip_miles IS NULL)                   AS null_trip_miles
    , COUNTIF(pickup_census_tract IS NULL)          AS null_pickup_census_tract
    , COUNTIF(dropoff_census_tract IS NULL)         AS null_dropoff_census_tract
    , COUNTIF(pickup_community_area IS NULL)        AS null_pickup_community_area
    , COUNTIF(dropoff_community_area IS NULL)       AS null_dropoff_community_area
    , COUNTIF(fare IS NULL)                         AS null_fare
    , COUNTIF(tips IS NULL)                         AS null_tips
    , COUNTIF(tolls IS NULL)                        AS null_tolls
    , COUNTIF(extras IS NULL)                       AS null_extras
    , COUNTIF(trip_total IS NULL)                   AS null_trip_total
    , COUNTIF(payment_type IS NULL)                 AS null_payment_type
    , COUNTIF(company IS NULL)                      AS null_company
    , COUNTIF(pickup_location IS NULL)              AS null_pickup_location
    , COUNTIF(dropoff_location IS NULL)             AS null_dropoff_location
  FROM `taxi-chicago-portfolio.taxi_data.trips_base`
--  WHERE partition_month >= '2022-01-01'                                   -- zakomentowne części pod analizę lat 2022 i 2023
  WHERE partition_month >= '2013-01-01' 
  GROUP BY 1 --,2
)

SELECT
    year
  --, month                                                                 -- zakomentowne części pod analizę lat 2022 i 2023
  --, distinct_days
  , total_rows
  , ROUND(null_trip_end_timestamp     / total_rows * 100, 2) AS trip_end_timestamp_null_pct
  , ROUND(null_trip_seconds           / total_rows * 100, 2) AS trip_seconds_null_pct
  , ROUND(null_trip_miles             / total_rows * 100, 2) AS trip_miles_null_pct
  , ROUND(null_pickup_census_tract    / total_rows * 100, 2) AS pickup_census_tract_null_pct      
  , ROUND(null_dropoff_census_tract   / total_rows * 100, 2) AS dropoff_census_tract_null_pct
  , ROUND(null_pickup_community_area  / total_rows * 100, 2) AS pickup_community_area_null_pct
  , ROUND(null_dropoff_community_area / total_rows * 100, 2) AS dropoff_community_area_null_pct
  , ROUND(null_fare                   / total_rows * 100, 2) AS fare_null_pct
  , ROUND(null_tips                   / total_rows * 100, 2) AS tips_null_pct
  , ROUND(null_tolls                  / total_rows * 100, 2) AS tolls_null_pct
  , ROUND(null_extras                 / total_rows * 100, 2) AS extras_null_pct
  , ROUND(null_trip_total             / total_rows * 100, 2) AS trip_total_null_pct
  , ROUND(null_payment_type           / total_rows * 100, 2) AS payment_type_null_pct
  , ROUND(null_company                / total_rows * 100, 2) AS company_null_pct
  , ROUND(null_pickup_location        / total_rows * 100, 2) AS pickup_location_null_pct
  , ROUND(null_dropoff_location       / total_rows * 100, 2) AS dropoff_location_null_pct
FROM count_of_nulls
ORDER BY year ASC;
--ORDER BY year, month ASC;                                                 -- zakomentowne części pod analizę lat 2022 i 2023

/*  
  | Year | Total Rows | End TS | Secs | Miles |Census (P/D)| Comm Area (P/D)| Company|
  |------|------------|--------|------|-------|------------|----------------|--------|
  | 2013 | 27,403,114 | 0.02%  | 3.97%| 0.00% | 34% / 35%  | 10% / 13%      | 28.15% |
  | 2014 | 47,477,237 | 0.02%  | 0.61%| 0.00% | 32% / 32%  | 11% / 13%      | 20.90% |
  | 2015 | 23,031,217 | 0.01%  | 0.02%| 0.00% | 34% / 34%  | 12% / 14%      | 41.66% |
  | 2016 | 28,527,313 | 0.01%  | 0.01%| 0.00% | 32% / 31%  | 9% / 10%       | 11.67% |
  | 2017 | 24,476,844 | 0.00%  | 0.01%| 0.00% | 30% / 31%  | 7% / 9%        | 0.00%  |
  | 2018 | 20,422,873 | 0.00%  | 0.01%| 0.00% | 29% / 30%  | 5% / 8%        | 0.00%  |
  | 2019 | 21,552,237 | 0.00%  | 0.02%| 0.00% | 33% / 34%  | 6% / 9%        | 0.00%  |
  | 2020 | 7,777,662  | 0.01%  | 0.04%| 0.00% | 54% / 54%  | 7% / 9%        | 0.00%  |
  | 2021 | 7,895,352  | 0.02%  | 0.04%| 0.01% | 71% / 71%  | 7% / 11%       | 0.00%  |
  | 2022 | 2,790,182  | 0.01%  | 0.02%| 0.00% | 67% / 66%  | 8% / 10%       | 0.00%  |
  | 2023 | 130,788    | 0.00%  | 0.03%| 0.00% | 66% / 68%  | 11% / 21%      | 0.00%  |
  (P/D) - (Pickup/Drop)

  Wnioski:
  1. Dopiero od 2017 można sensownie analizować po firmie, ponieważ wcześniej jest dużo braków.
  2. Do analizy przestrzeni pole community_area będzie lepsze od pola census_tract (dodatkowo census_tract ma wyraźnie więcej nulli od 2020 r.)
  3. Dostrzegalne jest załamanie kursów od wprowadzenia lockdownów w 2020r. Jednak rok 2022 i 2023 ma dodatkową przyczynę spadku.
  4. Dodałem zakomentowane elementy sprawdzające czy rok 2022 i 2023 ma niepełne dane. 
  Poniżej wynik grupowania z miesiącem i liczbą dni na te dwa lata. Dodałem podsumowującą kolumnę Status opierającą się o Total Rows i Days:

  | Year | Mo | Days | Total Rows | End TS | Secs | Miles | Census (P/D) | Comm Area (P/D) | Status |
  |------|----|------|------------|--------|------|-------|--------------|-----------------|--------|
  | 2022 | 01 | 31   | 598,643    | 0.00%  | 0.03%| 0.01% | 78% / 79%    | 8% / 11%        | OK     |
  | 2022 | 02 | 28   | 727,656    | 0.01%  | 0.02%| 0.00% | 71% / 71%    | 8% / 10%        | OK     |
  | 2022 | 03 | 31   | 512,274    | 0.00%  | 0.02%| 0.00% | 62% / 62%    | 9% / 11%        | OK     |
  | 2022 | 04 | 30   | 32,934     | 0.00%  | 0.05%| 0.00% | 65% / 65%    | 9% / 12%        | LOW    |
  | 2022 | 05 | 31   | 711,024    | 0.00%  | 0.02%| 0.00% | 58% / 57%    | 9% / 10%        | OK     |
  | 2022 | 06 | 1    | 4          | 0.00%  | 0.00%| 0.00% | 100% / 100%  | 0% / 0%         | BROKEN |
  | 2022 | 07 | 1    | 26,619     | 0.00%  | 0.01%| 0.00% | 66% / 65%    | 7% / 9%         | BROKEN |
  | 2022 | 08 | 31   | 18,603     | 0.04%  | 0.08%| 0.00% | 85% / 81%    | 49% / 48%       | LOW    |
  | 2022 | 09 | 1    | 4          | 0.00%  | 0.00%| 0.00% | 100% / 100%  | 50% / 100%      | BROKEN |
  | 2022 | 11 | 1    | 44,830     | 0.02%  | 0.02%| 0.00% | 43% / 43%    | 4% / 6%         | BROKEN |
  | 2022 | 12 | 31   | 117,591    | 0.02%  | 0.04%| 0.00% | 62% / 62%    | 10% / 13%       | LOW    |
  | 2023 | 01 | 1    | 2          | 0.00%  | 0.00%| 0.00% | 100% / 100%  | 0% / 0%         | BROKEN |
  | 2023 | 03 | 1    | 31,712     | 0.01%  | 0.02%| 0.00% | 56% / 56%    | 4% / 9%         | BROKEN |
  | 2023 | 04 | 30   | 10,632     | 0.00%  | 0.02%| 0.00% | 91% / 93%    | 45% / 63%       | LOW    |
  | 2023 | 05 | 1    | 2          | 0.00%  | 0.00%| 0.00% | 100% / 100%  | 100% / 100%     | BROKEN |
  | 2023 | 06 | 1    | 28,860     | 0.00%  | 0.02%| 0.01% | 56% / 58%    | 2% / 8%         | BROKEN |
  | 2023 | 07 | 31   | 9,856      | 0.00%  | 0.06%| 0.00% | 89% / 94%    | 37% / 64%       | LOW    |
  | 2023 | 09 | 1    | 19,334     | 0.00%  | 0.01%| 0.00% | 58% / 59%    | 1% / 7%         | BROKEN |
  | 2023 | 10 | 31   | 9,362      | 0.00%  | 0.11%| 0.00% | 89% / 95%    | 34% / 64%       | LOW    |
  | 2023 | 12 | 1    | 21,028     | 0.00%  | 0.02%| 0.00% | 71% / 72%    | 1% / 7%         | BROKEN |

  Wnioski:
  Po wyniku widać, że wszystkie okresy ze statusem LOW i BROKEN są wybrakowane. W efekcie lata 2022–2023 są niepełne 
  i nie nadają się do pełnych analiz trendów.
*/

# ============================================================
# Metody płatności - analiza unikatów (2013-2023)
# ============================================================

SELECT 
  payment_type, 
  COUNT(*)              AS total_occurrences,
  MIN(partition_month)  AS first_seen,
  MAX(partition_month)  AS last_seen
FROM `taxi-chicago-portfolio.taxi_data.trips_base`
WHERE partition_month >= '2013-01-01'
GROUP BY 1
ORDER BY 2 DESC;

/*
  | Rank | Payment Type  | Occurrences | First Seen | Last Seen  |
  |------|---------------|-------------|------------|------------|
  | 1    | Cash          | 121,298,248 | 2013-01-01 | 2023-12-01 |
  | 2    | Credit Card   | 84,076,224  | 2013-01-01 | 2023-12-01 |
  | 3    | Prcard        | 2,017,537   | 2013-08-01 | 2023-12-01 |
  | 4    | Unknown       | 1,630,282   | 2013-01-01 | 2023-12-01 |
  | 5    | Mobile        | 1,518,090   | 2017-01-01 | 2023-12-01 |
  | 6    | No Charge     | 810,443     | 2013-01-01 | 2023-12-01 |
  | 7    | Dispute       | 94,358      | 2013-01-01 | 2023-12-01 |
  | 8    | Pcard         | 33,860      | 2013-01-01 | 2019-05-01 |
  | 9    | Split         | 3,442       | 2017-08-01 | 2018-09-01 |
  | 10   | Prepaid       | 2,197       | 2017-11-01 | 2022-03-01 |
  | 11   | Way2ride      | 138         | 2016-08-01 | 2016-12-01 |

  Wnioski:
  1. Widzę niespójność w nazewnictwie kart korporacyjnych: 'Prcard' (2M) oraz 
    'Pcard' (33k). W warstwie silver zostaną one skonsolidowane do kategorii 'Card' wraz z podobnymi.

  2. Ewolucja Rynku:
    Płatności 'Mobile' pojawiły się w zbiorze dopiero w 2017 roku, co odzwierciedla 
    wejście na rynek nowoczesnych aplikacji płatniczych.

  3. Strategia Kategoryzacji na etap warstwy silver:
    - 'Card'   : Konsolidacja (Credit Card, Prcard, Pcard, Prepaid, Way2ride)
    - 'Cash'   : Bez zmian (Główna metoda płatności)
    - 'Mobile' : Bez zmian (Kluczowy trend wzrostowy)
    - 'No Pay' : Konsolidacja (No Charge, Dispute) dla analizy strat operacyjnych
    - 'Other'  : (Split, Unknown, NULL) dla zachowania czystości wykresów
*/
