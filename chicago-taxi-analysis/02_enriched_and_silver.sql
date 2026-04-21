
# ============================================================
# Weryfikacja anomalii - widok v_trips_enriched
# ============================================================

CREATE OR REPLACE VIEW `taxi-chicago-portfolio.taxi_data.v_trips_enriched` AS
SELECT
    *,
    CASE  WHEN company IS NULL 
          THEN 'Independent / Unknown'
          ELSE TRIM(REGEXP_REPLACE(company, r'[\.\s]+$', '')) 
    END                                                                          AS company_clean,       -- normalizacja nazwy firmy
    trip_miles * 1.609344                                                        AS trip_km,             -- odległość w km
    SAFE_DIVIDE(trip_seconds, 60.0)                                              AS duration_min,        -- czas w min
    SAFE_DIVIDE(trip_seconds, 3600.0)                                            AS duration_hr,         -- czas w h
    SAFE_DIVIDE(trip_miles * 1.609344, SAFE_DIVIDE(trip_seconds, 3600.0))        AS avg_speed_kmh,       -- śr. prędkość km/h
    SAFE_DIVIDE(trip_total, trip_miles * 1.609344)                               AS dollars_per_km,      -- $/km
    SAFE_DIVIDE(trip_total, SAFE_DIVIDE(trip_seconds, 60.0))                     AS dollars_per_min,     -- $/min
    (COALESCE(fare,0) + COALESCE(tips,0) + 
     COALESCE(tolls,0) + COALESCE(extras,0))                                     AS component_sum,       -- suma komponentów kosztu przejazdu
    (trip_total - (COALESCE(fare,0) + COALESCE(tips,0) + 
                   COALESCE(tolls,0) + COALESCE(extras,0)))                      AS component_gap,       -- rozjazd trip_total - komponenty

    (pickup_community_area IS NOT NULL 
     AND dropoff_community_area IS NOT NULL)                                     AS has_geo,             -- czy ma pickup i dropoff community_area
    (pickup_community_area IN (56, 76) 
     OR dropoff_community_area IN (56, 76))                                      AS is_airport_trip,     -- lotniska 76 - O'Hare (ORD), 56 - Midway (MDW)
    (trip_total IS NOT NULL AND ABS(trip_total - (COALESCE(fare,0) + 
     COALESCE(tips,0) + COALESCE(tolls,0) + COALESCE(extras,0))) <= 1)           AS is_total_consistent, -- czy jest spójność w przychodzie i jego składowych
    CASE 
      WHEN LOWER(payment_type) LIKE '%card%'
        OR LOWER(payment_type) LIKE '%pcard%'
        OR LOWER(payment_type) LIKE '%prcard%'
        OR LOWER(payment_type) LIKE '%prepaid%'
        OR LOWER(payment_type) LIKE '%way2ride%'
        THEN 'Card'                                   -- 1. KARTY (standardowe, literówki Prcard/Pcard, Prepaid, historyczne Way2ride)
      WHEN LOWER(payment_type) = 'cash'
        THEN 'Cash'                                   -- 2. GOTÓWKA
      WHEN LOWER(payment_type) = 'mobile'
        THEN 'Mobile'                                 -- 3. PŁATNOŚCI MOBILNE (Aplikacje)
      WHEN LOWER(payment_type) IN ('no charge', 'dispute')
        THEN 'No Charge/Dispute'                      -- 4. BRAK ZAPŁATY / REKLAMACJE (ważne dla analizy strat)
      WHEN payment_type IS NULL
        OR LOWER(payment_type) IN ('unknown', 'split')
        THEN 'Other/Unknown'                          -- 5. RESZTA (Split rzadkie ~3k, Unknown i NULL)
      ELSE 'Other/Unknown'
    END                                                                          AS payment_category    -- payment_category
FROM `taxi-chicago-portfolio.taxi_data.trips_base`;

/*
  Rozbudowuję tabelę o użyteczne pola. Porządkuję nazwy firm, metody płatności, dodaję flagi itd.
  Utworzony tu widok v_trips_enriched chcę zastosować w podsumowaniu wyniku audytu jakości tego datasetu oraz potem w utworzeniu 
  warstwy silver do analizy właściwej.

  Następnie wykonuję dalszą ocenę jakości danych, sprawdzając % śmieciowych rekordów, błędów, nietypowych zjawisk.
*/

# ============================================================
# WYNIK AUDYTU JAKOŚCI (2013-2023)
# ============================================================

SELECT
    EXTRACT(YEAR FROM trip_start_timestamp)                         AS trip_year,
    COUNT(*)                                                        AS total_rows,

  -- 1. Anomalie krytyczne  
    COUNTIF(COALESCE(trip_seconds,0) = 0 
            AND COALESCE(trip_km,0) = 0)                            AS ghost_trips,            -- 0s i 0km jednocześnie
    COUNTIF(trip_end_timestamp < trip_start_timestamp)              AS end_before_start,       -- koniec przed startem
    COUNTIF(trip_seconds > 0 
            AND trip_km > 0 
            AND trip_total = 0)                                     AS nonzero_trip_zero_pay,  -- kurs był, ale $0

  -- 2. Anomalie fizyczne i biznesowe
    COUNTIF(avg_speed_kmh > 130)                                    AS impossible_speed,       -- >130 km/h
    COUNTIF(duration_hr > 6)                                        AS extreme_duration,       -- >6h kursu
    COUNTIF(trip_total > 500)                                       AS extreme_total,          -- >500$ za kurs
    COUNTIF(dollars_per_min > 10 
            AND duration_min > 1)                                   AS extreme_cost_min,       -- >10$/min przy kursie >1min
    COUNTIF(trip_km > 300)                                          AS extreme_distance,       -- >300km
    
  -- 3. Statystyki jakościowe i biznesowe
    COUNTIF(NOT is_total_consistent)                                AS total_mismatch,         -- rozjazd komponentów > 1$
    COUNTIF(NOT has_geo)                                            AS missing_geo,            -- brak community_area
    COUNTIF(is_airport_trip)                                        AS airport_trips,          -- kursy lotniskowe
    COUNTIF(payment_category = 'Other/Unknown')                     AS payment_unknown,        -- nieznana metoda płatności
    COUNTIF(payment_category = 'No Charge/Dispute')                 AS payment_no_revenue,     -- brak przychodu

    -- 4. Wskaźniki procentowe (%)
    ROUND(SAFE_DIVIDE(
        COUNTIF(COALESCE(trip_seconds,0) = 0 AND COALESCE(trip_km,0) = 0),
        COUNT(*)) * 100, 3)                                         AS ghost_pct,
    ROUND(SAFE_DIVIDE(
        COUNTIF(avg_speed_kmh > 130),
        COUNT(*)) * 100, 3)                                         AS speed_pct,
    ROUND(SAFE_DIVIDE(
        COUNTIF(NOT is_total_consistent),
        COUNT(*)) * 100, 3)                                         AS mismatch_pct

FROM `taxi-chicago-portfolio.taxi_data.v_trips_enriched`
WHERE partition_month >= '2013-01-01'
GROUP BY 1
ORDER BY 1 DESC;

/*
  | Year | Total Rows | Ghost Trips | End<Start | Nonzero $0 | >130 km/h | >6h  | >$500 | >$10/min | >300km |
  |------|------------|------------:|----------:|-----------:|----------:|-----:|------:|---------:|-------:|
  | 2023 |     130,788|       3,220 |         2 |         78 |       132 |  130 |    22 |      464 |      8 |
  | 2022 |   2,790,182|      71,458 |        27 |      1,202 |     3,391 |2,652 |   446 |    5,129 |    116 |
  | 2021 |   7,895,352|     245,168 |       244 |      8,386 |    11,032 |7,715 | 2,320 |   13,940 |    412 |
  | 2020 |   7,777,662|     201,054 |       646 |      4,246 |     6,088 |6,724 | 3,048 |    8,486 |    250 |
  | 2019 |  21,552,237|     395,162 |       668 |        532 |    15,796 |12,602| 3,927 |   19,144 |    471 |
  | 2018 |  20,422,873|     255,046 |       426 |        695 |    31,651 |9,897 | 1,335 |   13,080 |    328 |
  | 2017 |  24,476,844|     352,079 |       544 |        813 |    40,260 |6,015 | 1,276 |    9,220 |    368 |
  | 2016 |  28,527,313|     534,030 |       818 |        860 |   341,016 |7,952 | 1,741 |   12,668 | 15,053 |
  | 2015 |  23,031,217|   1,430,399 |     1,782 |      1,082 |    39,272 |5,991 | 3,121 |    7,017 |  5,032 |
  | 2014 |  47,477,237|   4,444,928 |    89,033 |      9,701 |    60,448 |16,862| 4,887 |   11,076 |  1,558 |
  | 2013 |  27,403,114|   2,372,582 |   330,861 |      6,661 |   153,567 |8,373 | 6,263 |   16,936 |  2,970 |

  | Year | Total Mismatch | Missing Geo | Airport Trips | Payment Unknown | No Charge/Dispute | Ghost % | Speed % | Mismatch % |
  |------|---------------:|------------:|--------------:|----------------:|------------------:|--------:|--------:|-----------:|
  | 2023 |            760 |      30,870 |        36,418 |           5,668 |               112 |   2.462 |   0.101 |      0.581 |
  | 2022 |         10,218 |     418,590 |       575,961 |         184,722 |             3,399 |   2.561 |   0.122 |      0.366 |
  | 2021 |         66,788 |   1,159,280 |     1,599,312 |         667,170 |            10,752 |   3.105 |   0.140 |      0.846 |
  | 2020 |         23,382 |     855,856 |       907,296 |         346,502 |            14,868 |   2.585 |   0.078 |      0.301 |
  | 2019 |         34,687 |   2,192,206 |     3,219,492 |         152,675 |            48,797 |   1.834 |   0.073 |      0.161 |
  | 2018 |         22,719 |   1,756,754 |     2,903,933 |          54,956 |            38,961 |   1.249 |   0.155 |      0.111 |
  | 2017 |          4,167 |   2,508,125 |     3,204,447 |          35,629 |            61,221 |   1.438 |   0.164 |      0.017 |
  | 2016 |            441 |   3,486,354 |     3,586,218 |          30,835 |            77,553 |   1.872 |   1.195 |      0.002 |
  | 2015 |            471 |   3,426,905 |     2,531,830 |          22,032 |            71,994 |   6.211 |   0.171 |      0.002 |
  | 2014 |            802 |   6,523,316 |     4,698,607 |          75,685 |           256,957 |   9.362 |   0.127 |      0.002 |
  | 2013 |            582 |   3,755,785 |     2,550,469 |          57,850 |           320,187 |   8.658 |   0.560 |      0.002 |

  INTERPRETACJA:

  1) Największy red flag: Ghost Trips (0s i 0km)
    - 2013-2015: bardzo wysokie (~9% w 2013-2014, ~6% w 2015). Lata 2013–2015 mają wyraźnie więcej ghost trips i anomalii czasowych.
    - 2016-2020: stabilizacja ~1.2%–2.6%
    - 2021: skok do 3.1%, potem 2022-2023 ~2.5%

  2) Drugi red flag: end_before_start
    - Ekstremalnie dużo w 2013 (330,861) i 2014 (89,033), potem praktycznie zanika.

  3) Niemożliwie wysoka prędkość (>130 km/h)
    - 2016 wybija się: speed_pct = 1.195% (341,016 wierszy).

  4) Niezgodność na przychodzie (component_gap > 1)
    - Generalnie dane są poprawne. 2017-2018 bardzo nisko (0.017% i 0.111%), 2019-2023 rośnie do 0.58% (2023) i 0.85% (2021). 

  5) Brak community_area
    - Skala ogromna (miliony rocznie), ale to stały element wszystkich lat (a 2023 i 2022 są generalnie wybrakowane).

  6) Kursy lotniskowe (airport_trips)
    - Duży i stabilny segment (miliony w latach z dużym wolumenem). Zasługuje na osobną analizę.

  7) Kursy bez opłat (payment_no_revenue)
    - Są dziesiątki tysięcy rocznie w latach dużego wolumenu (np. 2019: 48,797). To mogą być straty operacyjne / reklamacje.
*/

# ========================================================================================================================
# Warstwa silver - (clean + validated + dedup + enriched) 'trips_silver'
# ========================================================================================================================

CREATE OR REPLACE TABLE `taxi-chicago-portfolio.taxi_data.trips_silver`
PARTITION BY partition_month
CLUSTER BY company_clean, taxi_id, payment_category, pickup_community_area
OPTIONS (require_partition_filter = TRUE)
AS

WITH validated AS (
    SELECT *
    FROM `taxi-chicago-portfolio.taxi_data.v_trips_enriched`
    WHERE
        partition_month >= '2013-01-01'

        -- A. Filtry Finansowe
        AND (fare IS NULL OR fare >= 0) 
        AND (tips IS NULL OR tips >= 0)
        AND (trip_total IS NULL OR trip_total >= 0)                                   -- odrzucam rekordy z ujemnymi kwotami
        AND (trip_total IS NULL OR trip_total <= 500)                                 -- odrzucam niemożliwie kosztowne kursy
        AND NOT (dollars_per_km > 50 AND trip_km > 1.0)                               -- odrzucam rekordy z niemożliwie wysokim kosztem/km
        
        -- B. Filtry Logiczne i Czasowe
        AND trip_end_timestamp >= trip_start_timestamp                                -- odrzucam czas startu > czasu końca
        AND NOT (COALESCE(trip_seconds, 0) = 0 AND COALESCE(trip_km, 0) = 0)          -- odrzucam ghost_trips
        AND (trip_seconds IS NULL OR trip_seconds <= 6 * 3600)                        -- odrzucam ponad 6 godzinne kursy
        AND NOT (COALESCE(trip_total, 0) = 0 AND (trip_seconds > 0 OR trip_km > 0))   -- odrzucam kursy z trasą/czasem bez opłaty
        
        -- C. Filtry Fizyczne (Outliers)
        AND (trip_km IS NULL OR trip_km <= 300)                                       -- odrzucam zbyt dalekie trasy
        AND (avg_speed_kmh IS NULL OR avg_speed_kmh <= 130)                           -- odrzucam rekordy z niemożliwie wysoką prędkością
),

deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY taxi_id, trip_start_timestamp
    ORDER BY 
      trip_total DESC,  
      trip_seconds DESC, 
      trip_miles DESC,
      unique_key         
      )                                                  AS row_num   -- odrzucam zdublowane rekordy, jeśli rekord ma to samo taxi id i czas startu
    FROM validated
)

SELECT * EXCEPT (row_num)
FROM deduped
WHERE row_num = 1;

/*
  Na podstawie audytu jakości usuwam zbędne rekordy tworząc upragnioną warstwę silver.
  Total logical bytes 72.1 GB, a oryginalna baza 76.75 GB. Wychodzi mniej o 4,6 GB, około ~6%. 
  Następnie w celu dalszej redukcji zużycia transferu tworzę data marts dla 3 interesujących mnie obszarów.
  Każdy data mart to kilkanaście GB, a raporty na jego bazie to już tylko okolice 1 MB :)
*/
