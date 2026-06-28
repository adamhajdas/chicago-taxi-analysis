
# ************************************************************************************************************************
# ========================================================================================================================
# RAPORTY
# ========================================================================================================================
# ************************************************************************************************************************

# ========================================================================================================================
# 1. MART: Wydajność Firm (do rankingów) 'mart_company_performance'
# ========================================================================================================================

CREATE OR REPLACE TABLE `taxi-chicago-portfolio.taxi_data.mart_company_performance`
PARTITION BY month_start
CLUSTER BY company_clean, payment_category, is_airport_trip
OPTIONS (
  require_partition_filter = TRUE
)
AS
SELECT
  DATE_TRUNC(DATE(trip_start_timestamp), MONTH)         AS month_start,
  company_clean,
  COALESCE(payment_category, 'Other/Unknown')           AS payment_category,
  COALESCE(is_airport_trip, FALSE)                      AS is_airport_trip,
  COUNT(*)                                              AS trip_count,
  COUNT(DISTINCT taxi_id)                               AS active_taxis,
  SUM(COALESCE(trip_total, 0))                          AS total_revenue,
  SUM(COALESCE(fare, 0))                                AS total_fare,
  SUM(COALESCE(tips, 0))                                AS total_tips,
  SUM(COALESCE(trip_km, 0))                             AS total_trip_km,
  SUM(COALESCE(duration_min, 0))                        AS total_duration_min
FROM `taxi-chicago-portfolio.taxi_data.trips_silver`
WHERE partition_month BETWEEN '2017-01-01' AND '2021-12-01' 
GROUP BY 1,2,3,4;

# ============================================================
# FIRMY I NAPIWKI
# ============================================================

SELECT 
  company_clean,                                                                              -- analiza per firma
  ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(trip_count)), 2)        AS avg_trip_total,        -- średni przychód na kurs
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_trip_km)), 4)        AS tips_per_km,           -- napiwek/km
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_duration_min)), 4)   AS tips_per_min,          -- napiwek/min
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_revenue)), 4)        AS tip_share_of_revenue   -- napiwek/całkowity przychód
FROM `taxi-chicago-portfolio.taxi_data.mart_company_performance` 
WHERE 
  month_start BETWEEN '2017-01-01' AND '2021-12-01'                                           -- 2017-2021, żeby mieć pełne dane dotyczące firm
GROUP BY company_clean
HAVING SUM(trip_count) >= 1000;                                                               -- Filtr 1000 kursów eliminuje firmy o znaczeniu marginalnym

/*
  |Sortowanie poglądowo po Avg Trip $:

  | Rank | Company Name                 | Avg Trip $ | Tips/KM | Tips/Min | Tip Share |
  |------|------------------------------|------------|---------|----------|-----------|
  | 1    | U Taxicab                    |  30.16     | 0.2410  | 0.1495   | 10.08%    |
  | 2    | 312 Medallion Management     |  27.58     | 0.2842  | 0.1722   | 12.16%    |
  | 3    | Top Cab Affiliation          |  21.45     | 0.2709  | 0.1412   | 10.95%    |
  | 4    | Taxicab Insurance Agency     |  20.59     | 0.3166  | 0.1476   | 11.25%    |
  | 5    | Choice Taxi Association      |  18.82     | 0.3198  | 0.1442   | 11.82%    |

  Sortując malejąco po poszczególnych metrykach mamy następujący ranking:
  U Taxicab - po Avg Trip $ 
  Mistrz wartości bezwzględnej (długie trasy, wysoki bilet wstępu, prawdopodobnie transfery międzymiastowe/lotniskowe).

  Blue Ribbon - po Tips/KM
  Mistrz intensywności miejskiej (wysoki tip na kilometr, krótkie trasy, walka w korkach w centrum). Mocno odstają pod względem tips_per_km od reszty.

  312 Medallion Management Corp - po Tips/Min
  Ich kierowcy otrzymują najwięcej napiwku na każdą minutę pracy. Przy tym mają też bardzo duży tip_share_of_revenue, więc jest to firma realizująca bardzo drogie kursy.

  303 Taxi - po Tip Share
  Najwyższy udział napiwku do przychodu, ale stosunkowo niski avg_trip_total, tips_per_min i tips_per_km. Pasażerowie zostawiają tam relatywnie wysokie napiwki (procentowo) 
  względem bardzo niskiej ceny kursu.
*/

# ============================================================
# RANKING: UDZIAŁ W RYNKU I KONCENTRACJA (2017-2021)
# ============================================================

WITH company_totals AS (
  SELECT
    company_clean,                                                          -- analiza per firma
    SUM(trip_count)     AS trips,
    SUM(total_revenue)  AS revenue
  FROM `taxi-chicago-portfolio.taxi_data.mart_company_performance`
  WHERE month_start BETWEEN  '2013-01-01' AND '2022-01-01'                  --  2017-2021, żeby mieć pełne dane dotyczące firm
  GROUP BY 1
),

market_totals AS (                                                          -- wyjmuję sumy całkowite, żeby mieć do mianownika w dzielniu 
  SELECT
    SUM(trips)          AS total_trips,
    SUM(revenue)        AS total_revenue
  FROM company_totals
)

SELECT
  c.company_clean,                                                                    
  c.trips,                                                                      -- liczba tras
  ROUND(c.revenue, 2)                                     AS revenue,           -- suma przychodów
  ROUND(SAFE_DIVIDE(c.trips, m.total_trips) * 100, 2)     AS trip_share_pct,    -- udział w trasach
  ROUND(SAFE_DIVIDE(c.revenue, m.total_revenue) * 100, 2) AS revenue_share_pct  -- udział w przychodach
FROM company_totals         c
  CROSS JOIN market_totals  m
WHERE c.trips >= 1000                                                           -- bez małych podmiotów
ORDER BY revenue_share_pct DESC;

/*
  Poniższe zestawienie przedstawia 5 największych graczy, którzy dominują na rynku 
  taxi w Chicago, kontrolując łącznie ponad połowę całego obrotu.

  | Rank | Company Name                 | Trips     | Revenue ($)    | Trip Share | Rev Share |
  |------|------------------------------|-----------|----------------|------------|-----------|
  | 1    | Flash Cab                    | 9,895,923 | 180,424,380.23 | 15.71%     | 16.07%    |
  | 2    | Taxi Affiliation Services    | 9,220,003 | 160,878,939.82 | 14.64%     | 14.33%    |
  | 3    | Chicago Carriage Cab Corp    | 6,111,142 | 111,594,878.57 |  9.70%     |  9.94%    |
  | 4    | Sun Taxi                     | 4,107,310 |  81,152,193.94 |  6.52%     |  7.23%    |
  | 5    | City Service                 | 4,063,501 |  74,987,121.28 |  6.45%     |  6.68%    |

  WNIOSKI Z ANALIZY STRUKTURY RYNKU:

  1. Dwaj najwięksi gracze (Flash Cab i Taxi Affiliation Services) kontrolują wspólnie 
    ponad 30% rynku. Rynek nie jest rozproszony równomiernie, są wyraźni liderzy.

  2. W przypadku liderów, udział w liczbie kursów (Trip Share) niemal idealnie pokrywa 
    się z udziałem w przychodzie (Rev Share).

  3. Top 5 firm agreguje ok. 54% całkowitego przychodu rynku. Pozostałe kilkadziesiąt 
    firm musi walczyć o nisze jak np. dłuższe kursy lotniskowe, krótsze kursy w centrach miast.

  Podsumowując: Rynek taxi w Chicago jest częściowo skoncentrowany – kilka dużych operatorów odpowiada 
  za znaczącą część wolumenu i przychodu, podczas gdy mniejsze firmy działają w bardziej wyspecjalizowanych niszach.
*/

# ============================================================
# METODY PŁATNICZE NA PRZESTRZENI LAT 2017-2021
# ============================================================

WITH base AS (
  SELECT
    EXTRACT(YEAR FROM month_start)    AS year,                          -- analiza per rok i metoda płatności
    payment_category,
    SUM(trip_count)                   AS trip_count,                    -- liczba tras
    SUM(total_revenue)                AS total_revenue                  -- całkowity przychód
  FROM `taxi-chicago-portfolio.taxi_data.mart_company_performance`
  WHERE month_start >= '2013-01-01' AND month_start < '2022-01-01'  
  GROUP BY 1, 2
)

SELECT
  year,
  payment_category,                                                           -- analiza per rok i metoda płatności
  trip_count,                                                                 -- liczba tras 
  ROUND(SAFE_DIVIDE(trip_count,                                                 
    SUM(trip_count) OVER (PARTITION BY year)), 4)     AS share_of_trips,      -- udział ilościowo w danym roku
  ROUND(total_revenue, 2)                             AS total_revenue,       -- kwota przychodu
  ROUND(SAFE_DIVIDE(total_revenue,
    SUM(total_revenue) OVER (PARTITION BY year)), 4)  AS share_of_revenue     -- udział w przychodach w danym roku
FROM base
ORDER BY year, share_of_trips DESC;

/*
  Wyświetlam poglądowo lata 2017-2021
  | YEAR | PAYMENT_CATEGORY    | TRIP_COUNT | SHARE_OF_TRIPS | TOTAL_REVENUE  | SHARE_OF_REVENUE|
  |------|---------------------|------------|----------------|----------------|-----------------|
  | 2017 | Cash                | 11,859,794 | 53.14%         | 148,762,000    | 40.17%          |
  | 2017 | Card                | 10,357,135 | 46.41%         | 220,007,000    | 59.40%          |
  | 2018 | Cash                | 9,283,758  | 49.85%         | 120,434,000    | 37.13%          |
  | 2018 | Card                | 9,145,656  | 49.11%         | 200,239,000    | 61.74%          |
  | 2019 | Card                | 7,535,984  | 50.74%         | 171,802,000    | 62.85%          |
  | 2019 | Cash                | 6,965,967  | 46.90%         | 94,745,200     | 34.66%          |
  | 2020 | Card                | 1,939,121  | 53.64%         | 48,157,400     | 67.57%          |
  | 2020 | Cash                | 1,598,393  | 44.22%         | 21,399,700     | 30.03%          |
  | 2021 | Card                | 2,246,552  | 58.74%         | 62,398,700     | 72.06%          |
  | 2021 | Cash                | 1,446,183  | 37.82%         | 21,460,100     | 24.78%          |

  WNIOSKI Z ANALIZY TRENDÓW PŁATNOŚCI (2017-2021):

1. WIELKI PRZEŁOM (2019):
  Rok 2019 był punktem zwrotnym, w którym płatności kartą po raz pierwszy wyprzedziły 
  gotówkę pod względem liczby kursów (50.7% vs 46.9%). Od tego momentu dominacja 
  bezkontaktowych form płatności stale rośnie.

2. PANDEMICZNY KATALIZATOR:
  Rok 2020 przyniósł gwałtowny odwrót od gotówki (spadek udziału w przychodach do 30%), 
  co prawdopodobnie wynikało z obaw higienicznych oraz popularyzacji płatności 
  bezdotykowych w trakcie COVID-19. Trend ten utrzymał się w 2021 r. (karta = 72% przychodu).

3. "CASH FOR SHORT, CARD FOR LONG":
  Zauważalna jest stała dysproporcja między udziałem w liczbie kursów a udziałem w przychodzie.
  Gotówka dominuje w tanich, krótkich kursach miejskich. Kursy opłacane kartą mają 
  znacznie wyższą wartość średnią (w 2021 r. karta to 58% kursów, ale aż 72% przychodu).

4. ROZWÓJ KANAŁU MOBILE:
  Choć płatności mobilne (Mobile) startowały z poziomu błędu statystycznego w 2017 (0.06%), 
  do 2021 roku ich udział wzrósł do 3% wolumenu. Jest to najszybciej rosnący, 
  choć wciąż niszowy kanał płatności.

5. WNIOSEK OPERACYJNY:
  System Taxi w Chicago przeszedł transformację z przewagi rozliczeń gotówkowych (2017) 
  do przejścia na płatności kartowe i mobilne (2021).

*/

# ========================================================================================================================
# 2. MART: Analiza w czasie (mart_time_analysis)
# ========================================================================================================================

CREATE OR REPLACE TABLE `taxi-chicago-portfolio.taxi_data.mart_time_analysis`
PARTITION BY month_start
CLUSTER BY day_of_week, hour_of_day
OPTIONS (
  require_partition_filter = TRUE
)
AS
SELECT
  DATE_TRUNC(DATE(trip_start_timestamp), MONTH) AS month_start,       -- analiza per miesiąc, dzień tygodnia, godzina
  EXTRACT(DAYOFWEEK FROM trip_start_timestamp)  AS day_of_week,       -- dzień tygodnia 1 = niedziela ... 7 = sobota
  EXTRACT(HOUR FROM trip_start_timestamp)       AS hour_of_day,       -- godzina 

  COUNT(*)                                      AS trip_count,        -- liczba kursów
  COUNTIF(COALESCE(tips, 0) > 0)                AS tipped_trip_count, -- liczba kursów z napiwkiem
  SUM(COALESCE(trip_total, 0))                  AS total_revenue,     -- suma przychodów
  SUM(COALESCE(tips, 0))                        AS total_tips,        -- suma z napiwków
  SUM(COALESCE(trip_km, 0))                     AS total_trip_km,     -- suma km
  SUM(COALESCE(duration_min, 0))                AS total_duration_min -- suma min

FROM `taxi-chicago-portfolio.taxi_data.trips_silver`
WHERE partition_month >= '2013-01-01' AND partition_month < '2022-01-01' -- wybieram zakres lat 2013-2021
GROUP BY 1,2,3;

# ============================================================
# DNI TYGODNIA I GODZINY NAJWIĘKSZYCH PRZYCHODÓW
# ============================================================

SELECT
  CASE day_of_week                                                       -- Dzień słownie dla poprawy czytelności
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END                                                                   AS day_name,
  hour_of_day,                                                                                    -- godzina        

  SUM(trip_count)                                                       AS trip_count,            -- liczba kursów
  ROUND(SUM(total_revenue), 2)                                          AS total_revenue,         -- suma przychodów
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(trip_count)), 4)               AS avg_tip_per_trip,      -- napiwek/kurs
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_revenue)), 4)            AS tip_share_of_revenue,  -- udział napiwków w całości
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_duration_min)), 4)       AS tips_per_min           -- napiwek/min
FROM `taxi-chicago-portfolio.taxi_data.mart_time_analysis`
WHERE month_start >= '2017-01-01'
GROUP BY day_name, hour_of_day
ORDER BY day_name, hour_of_day;

/*

WNIOSKI Z ANALIZY CZASOWEJ:

1. PEAK POPYTU VS PEAK NAPIWKÓW:
   Największy wolumen kursów (peak komunikacyjny) przypada na 17:00–19:00, 
   jednak najwyższa efektywność napiwków (tips_per_min) przesuwa się na godziny wieczorne (20:00–22:00).

2. DWA MODELE ZACHOWANIA PASAŻERÓW:
   - Godziny popołudniowe → wysoki wolumen, umiarkowane napiwki
   - Godziny wieczorne → niższy wolumen, ale wyższa hojność klientów

3. Środa wieczór jako mocny segment tygodnia:
   Wbrew intuicji, środa wieczór należy do najbardziej dochodowych okresów, 
   łącząc wysoki ruch z wysokimi napiwkami.

4. WCZESNE PORANKI - LIDER W avg_tip_per_trip:
   Godzina 5:00 rano, mimo niskiego wolumenu, charakteryzuje się najwyższymi jednostkowymi napiwkami (średnio o 15-20% wyższymi niż w szczycie porannym). 
   Wskazuje to na specyficzny segment klienta premium (np. transfery lotnicze, wczesny biznes), ale sumarycznie nie osiągają poziomu napiwków obserwowanego w godzinach wieczornych.

5. OPTYMALNY CZAS PRACY KIEROWCY:
   Przedział 20:00–22:00 jest najbardziej dochodowy dla kierowców w przeliczeniu na minutę pracy. 
   Łączy on wysoką hojność pasażerów (tip_share_of_revenue > 10%) z płynniejszym ruchem drogowym niż w godzinach popołudniowych.
*/

# ============================================================
# Analiza sezonowości
# ============================================================

SELECT
  EXTRACT(MONTH FROM month_start)                                         AS month_num,   -- analiza per miesiąc i utworzony sezon 
  FORMAT_DATE('%B', month_start)                                          AS month_name,
  CASE EXTRACT(MONTH FROM month_start)
    WHEN 12 THEN 'Winter' WHEN 1 THEN 'Winter' WHEN 2 THEN 'Winter'
    WHEN 3  THEN 'Spring' WHEN 4 THEN 'Spring' WHEN 5 THEN 'Spring'
    WHEN 6  THEN 'Summer' WHEN 7 THEN 'Summer' WHEN 8 THEN 'Summer'
    ELSE 'Autumn'
  END                                                                     AS season,    

  SUM(trip_count)                                                         AS trip_count,
  ROUND(SUM(total_revenue), 2)                                            AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(trip_count)), 4)                 AS avg_tip_per_trip,
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_revenue)), 4)              AS tip_share_of_revenue,
  ROUND(SAFE_DIVIDE(SUM(total_trip_km), SUM(trip_count)), 4)              AS avg_km_per_trip,
  ROUND(SAFE_DIVIDE(SUM(total_duration_min), SUM(trip_count)), 4)         AS avg_duration_min
FROM `taxi-chicago-portfolio.taxi_data.mart_time_analysis`
WHERE month_start BETWEEN '2013-01-01' AND '2019-12-01'                -- zmieniłem filtr do '2019-12-01', żeby efekty covida nie zaburzyły analizy
GROUP BY month_num, month_name, season
ORDER BY month_num;

/*
WNIOSEK ANALITYCZNY NR 3: SEZONOWOŚĆ I WPŁYW POGODY (2017-2019)

1. EFEKT "WINTER CHILL" (STYCZEŃ-LUTY):
  Najniższy wolumen w roku (ok. 10.5M kursów). Zima w Chicago zmusza pasażerów 
  do dłuższego planowania tras – średni dystans kursu (avg_km) jest o ok. 10% 
  wyższy niż w lecie. Taksówka staje się niezbędnym środkiem transportu 
  dalekobieżnego wewnątrz miasta.

2. SZCZYT TURYSTYCZNO-BIZNESOWY (MAJ-CZERWIEC | PAŹDZIERNIK):
  Największa aktywność przypada na przełom wiosny i lata oraz jesień. 
  Październik wyróżnia się jako najbardziej dochodowy miesiąc pod kątem 
  napiwków (avg_tip = 1.59$), co silnie koreluje z sezonem konferencyjnym 
  w Chicago (McCormick Place).

3. LATO I "KRÓTKIE SKOKI" (LIPIEC-SIERPIEŃ):
  Mimo wysokiego wolumenu, lato charakteryzuje się najkrótszymi dystansami 
  (avg_km = 5.6). Prawdopodobna przyczyna to duży udział turystów poruszających 
  się na krótkich odcinkach w strefie Downtown oraz liczne festiwale 
  (np. Lollapalooza), które generują ogromną liczbę krótkich przejazdów.

4. WNIOSKI OPERACYJNE:
  - Sezon zimowy: Strategia na długie trasy i stabilne, choć rzadsze przychody.
  - Sezon jesienny: Maksymalizacja zysków dzięki hojności klientów biznesowych.
  - Sezon letni: Strategia na "obrót" – duża liczba szybkich, krótkich kursów.
*/

# ========================================================================================================================
# 3. MART: Przepływy Geograficzne (mart_geo_flows)
# ========================================================================================================================

CREATE OR REPLACE TABLE `taxi-chicago-portfolio.taxi_data.mart_geo_flows`
PARTITION BY month_start
CLUSTER BY pickup_community_area, dropoff_community_area, is_airport_trip
OPTIONS (
  require_partition_filter = FALSE
)
AS
SELECT
  DATE_TRUNC(DATE(trip_start_timestamp), MONTH) AS month_start,         -- mart per miesiąc, obszar odbioru/dowozu oraz flaga czy kurs lotniskowy
  pickup_community_area,
  dropoff_community_area,
  is_airport_trip,

  COUNT(*)                                      AS trip_count,
  SUM(trip_total)                               AS total_revenue,
  SUM(trip_km)                                  AS total_trip_km,
  SUM(duration_min)                             AS total_duration_min,
  SUM(tips)                                     AS total_tips

FROM `taxi-chicago-portfolio.taxi_data.trips_silver`
WHERE partition_month BETWEEN '2017-01-01' AND '2021-12-01'
  AND pickup_community_area IS NOT NULL
  AND dropoff_community_area IS NOT NULL
GROUP BY 1, 2, 3, 4;

# ============================================================
# TOP 20 PRZYCHODOWYCH OBSZARÓW
# ============================================================

WITH activity AS (                                        -- dwie tabele do złączenia za pomocą union, żeby uzyskać jedno area
  SELECT 
    pickup_community_area          AS area,               -- ujęcie per obszar + określenie jego roli
    'Pickup'                       AS role,
    SUM(trip_count)                AS trip_count, 
    SUM(total_revenue)             AS total_revenue, 
    SUM(total_tips)                AS total_tips
  FROM `taxi-chicago-portfolio.taxi_data.mart_geo_flows`
  GROUP BY pickup_community_area                      

  UNION ALL

  SELECT 
    dropoff_community_area        AS area, 
    'Dropoff'                     AS role,
    SUM(trip_count)               AS trip_count, 
    SUM(total_revenue)            AS total_revenue, 
    SUM(total_tips)               AS total_tips
  FROM `taxi-chicago-portfolio.taxi_data.mart_geo_flows`
  GROUP BY dropoff_community_area
)

SELECT
  area,                                                              
  role,
  trip_count,
  ROUND(total_revenue, 2)                                     AS total_revenue,
  ROUND(SAFE_DIVIDE(total_tips, trip_count), 4)               AS avg_tip
FROM activity
QUALIFY ROW_NUMBER() OVER (PARTITION BY role ORDER BY trip_count DESC) <= 20
ORDER BY role, trip_count DESC;

/*
  | AREA | ROLE    | TRIP COUNT  | TOTAL REVENUE    | AVG TIP |
  |------|---------|-------------|------------------|---------|
  | 8    | Dropoff | 17,401,672  | 240,556,558.35   | $1.52   |
  | 8    | Pickup  | 18,460,001  | 232,106,822.11   | $1.29   |
  | 76   | Pickup  | 4,337,013   | 218,761,278.74   | $6.10   |
  | 32   | Pickup  | 15,347,422  | 197,025,633.50   | $1.49   |
  | 32   | Dropoff | 12,435,785  | 168,097,935.39   | $1.56   |
  | 76   | Dropoff | 2,263,523   | 105,169,442.32   | $5.18   |
  | 28   | Dropoff | 6,434,382   | 80,013,608.87    | $1.30   |
  | 28   | Pickup  | 6,157,786   | 74,173,927.06    | $1.17   |
  | 6    | Dropoff | 2,847,690   | 53,316,914.33    | $1.95   |
  | 56   | Pickup  | 1,167,715   | 49,295,811.49    | $4.99   |

1. DOMINACJA "THE LOOP" I NEAR NORTH SIDE:
  Obszary 8 (Near North Side), 32 (Loop) oraz 28 (Near West Side) generują 
  blisko 60% całego ruchu miejskiego. Są to centra biznesowe, turystyczne 
  i komunikacyjne Chicago. To tutaj bije "serce" systemu Taxi.

2. KORELACJA REVENUE Z LOKALIZACJĄ:
  Obszary o najwyższym avg_tip to zazwyczaj te związane z ruchem lotniskowym 
  (np. 76, 56) lub zamożnymi dzielnicami północnymi. W samym centrum (Loop) 
  napiwki są stabilne, ale niższe kwotowo ze względu na dużą liczbę 
  bardzo krótkich kursów.

3. ASYMETRIA PRZEPŁYWÓW:
  - Near North Side (8): Względna równowaga między wysiadającymi a wsiadającymi.
  - O'Hare (76): Potężna przewaga Pickup (4.3M) nad Dropoff (2.2M). 
    Obszar 76 jest "kopalnią przychodu" głównie dla kursów powrotnych do miasta.
  - Loop (32): Zauważalna przewaga wsiadających (Pickup), co może wiązać się 
    z dojazdami do pracy innymi środkami transportu i powrotami taksówką wieczorem.
*/

# ============================================================
# LOTNISKA A RESZTA RYNKU - PRZYCHODOWOŚĆ
# ============================================================

SELECT
  CASE
    WHEN pickup_community_area IN (76, 56) THEN 'Airport Pickup'
    WHEN dropoff_community_area IN (76, 56) THEN 'Airport Dropoff'
    ELSE 'Non-Airport'
  END                                                               AS segment,
  CASE
    WHEN pickup_community_area = 76 OR dropoff_community_area = 76 THEN 'OHare'
    WHEN pickup_community_area = 56 OR dropoff_community_area = 56 THEN 'Midway'
    ELSE 'City'
  END                                                               AS airport_name,

  SUM(trip_count)                                                   AS trip_count,
  ROUND(SUM(total_revenue), 2)                                      AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(trip_count)), 2)        AS avg_trip_value,
  ROUND(SAFE_DIVIDE(SUM(total_trip_km), SUM(trip_count)), 2)        AS avg_km,
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(trip_count)), 4)           AS avg_tip,
  ROUND(SAFE_DIVIDE(SUM(total_tips), SUM(total_revenue)), 4)        AS tip_share

FROM `taxi-chicago-portfolio.taxi_data.mart_geo_flows`
GROUP BY segment, airport_name
ORDER BY avg_trip_value DESC;

/*
  | SEGMENT          | AIRPORT NAME | TRIP COUNT | TOTAL REVENUE  | AVG TRIP | AVG KM | AVG TIP | TIP SHARE |
  |------------------|--------------|------------|----------------|----------|--------|---------|-----------|
  | Airport Dropoff  | OHare        | 1,859,771  | 96,300,768.66  | $51.78   | 24.82  | $5.94   | 11.47%    |
  | Airport Pickup   | OHare        | 4,350,346  | 219,905,300.46 | $50.55   | 22.47  | $6.10   | 12.07%    |
  | Airport Pickup   | Midway       | 1,154,382  | 48,151,789.77  | $41.71   | 17.15  | $4.97   | 11.91%    |
  | Airport Dropoff  | Midway       | 585,780    | 23,077,692.53  | $39.40   | 17.77  | $4.57   | 11.60%    |
  | Non-Airport      | City         | 48,862,603 | 561,779,022.30 | $11.50   | 3.29   | $1.06   | 9.19%     |

  WNIOSEK ANALITYCZNY: LOTNISKA VS RESZTA MIASTA (2017-2021):

1. KURS LOTNISKOWY = PREMIUM PRODUCT:
   Średnia wartość kursu z O'Hare ($51) jest ponad 4.5x wyższa niż w mieście ($11.50). 
   Mimo że lotniska to mniejszość wolumenu, generują one lwią część marży.

2. ASYMETRIA O'HARE:
   Liczba kursów "z lotniska" (Pickup) jest ponad 2-krotnie wyższa niż "na lotnisko" (Dropoff). 
   Sugeruje to, że taksówki wygrywają walkę o pasażera w strefie przylotów (wygoda postoju), 
   podczas gdy przy dojazdach na lotnisko pasażerowie częściej wybierają inne środki transportu.

3. KULTURA NAPIWKÓW:
   Udział napiwków w segmencie lotniskowym (~12%) jest o ok. 30% wyższy niż w mieście (9%). 
   Pasażer na długim dystansie jest skłonny wynagrodzić kierowcę znacznie hojniej.

4. WNIOSEK DLA ROZWOJU FLOTY:
   Mimo że kursy miejskie dominują wolumenem (48M), strategiczne pozycjonowanie taxi 
   w strefie przylotów O'Hare (Airport Pickup) jest najbardziej dochodową strategią 
   jednostkową w całym systemie transportowym Chicago.
*/

