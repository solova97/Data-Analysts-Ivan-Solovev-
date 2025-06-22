----Задача 1. Время активности объявлений
-- Определение аномальных значений по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Вывод id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Формирование таблицы flats из схемы real_estate без аномалий:
flats AS(
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id)
),
-- Вывод основных показателей для дальнейших подсчетов:
stats AS(
SELECT
	CASE 
		WHEN c.city = 'Санкт-Петербург'
		THEN 'Санкт-Петербург'
		ELSE 'ЛенОбл'
	END AS region,
	CASE
		WHEN a.days_exposition BETWEEN 1 AND 30	THEN 'до месяца'
		WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трех месяцев'
		WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
		WHEN a.days_exposition > 180 THEN 'более полугода'
	END AS segment, -- сегментирование рынка недвижимости по времени активности объявлений 
	a.last_price / f.total_area AS price_per_meter,
	f.total_area,
	f.rooms,
	f.balcony,
	f.floor,
	f.is_apartment,
	f.floors_total
FROM flats f
LEFT JOIN real_estate.advertisement a USING(id)
LEFT JOIN real_estate.city c USING(city_id)
LEFT JOIN real_estate.TYPE t USING(type_id)
WHERE t.TYPE = 'город' -- фильтр на города согласно ТЗ
	AND a.days_exposition IS NOT NULL -- исключение незавершенных публикаций для чистоты данных
),
-- СТЕ с основными расчетами по сегментам:
reg AS ( 
SELECT 
	region,
	segment,
	COUNT(COALESCE(rooms, 1)) AS total_exposition,
	ROUND(AVG(price_per_meter::NUMERIC), 2) AS avg_price_per_meter,
	ROUND(AVG(total_area::NUMERIC), 2) AS avg_area,
	ROUND(AVG(rooms::NUMERIC)) AS avg_rooms,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY rooms) AS median_rooms,
	ROUND(AVG(floor::NUMERIC)) AS avg_floor,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floor) AS median_floor,
	SUM(is_apartment) AS count_apartments,
	COUNT(rooms) FILTER(WHERE rooms = 0) AS count_studios,
	ROUND(AVG(floors_total::NUMERIC)) AS avg_house_floors,
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floors_total) AS median_house_floors
FROM stats
GROUP BY 1,2
)
-- Добавление оконных функций для расчета долей по регионам:
SELECT 
	region,
	segment,
	total_exposition,
	ROUND(total_exposition / SUM(total_exposition::NUMERIC) OVER(PARTITION BY region)*100, 2) AS exposition_perc,
	avg_price_per_meter,
	avg_area,
	avg_rooms,
	median_rooms,
	avg_floor,
	median_floor,
	avg_house_floors,
	median_house_floors,
	ROUND(count_studios / SUM(total_exposition::NUMERIC) OVER(PARTITION BY region)*100, 2) AS studios_perc,
	ROUND(count_apartments / SUM(total_exposition::NUMERIC) OVER(PARTITION BY region)*100, 2) AS apartments_perc
FROM reg
ORDER BY 1 DESC, 2;

----Задача 2. Сезонность объявлений
--Избавляемся от выбросов.
WITH limitations AS (
     SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
--Создаем фильтр по id квартир, в которых аномальные значения отсутствуют
filter_by_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limitations)
        AND (rooms < (SELECT rooms_limit FROM limitations) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limitations) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limitations)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limitations)) OR ceiling_height IS NULL)
 ),
 --Отбираем только нужные значения из таблицы flats
cleared_data AS(
     SELECT *
     FROM real_estate.advertisement
     WHERE id IN (SELECT * FROM filter_by_id)
),
data_for_calculation AS (
     SELECT
     cleared_data.id,
     first_day_exposition,
     EXTRACT(MONTH FROM first_day_exposition) AS first_day_exposition_month_number,
     CASE
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 1
	    THEN 'Январь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 2
	    THEN 'Февраль'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 3
	    THEN 'Март'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 4
	    THEN 'Апрель'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 5
	    THEN 'Май'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 6
	    THEN 'Июнь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 7
	    THEN 'Июль'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 8
	    THEN 'Август'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 9
	    THEN 'Сентябрь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 10
	    THEN 'Октябрь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 11
	    THEN 'Ноябрь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition) = 12
	    THEN 'Декабрь'
     END AS month_published,
     first_day_exposition + CAST(days_exposition AS integer) AS last_day_exposition,
     EXTRACT (MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) AS last_day_exposition_month_number,
     CASE
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 1
	    THEN 'Январь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 2
	    THEN 'Февраль'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 3
	    THEN 'Март'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 4
	    THEN 'Апрель'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 5
	    THEN 'Май'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 6
	    THEN 'Июнь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 7
	    THEN 'Июль'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 8
	    THEN 'Август'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 9
	    THEN 'Сентябрь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 10
	    THEN 'Октябрь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 11
	    THEN 'Ноябрь'
	   WHEN EXTRACT(MONTH FROM first_day_exposition + CAST(days_exposition AS integer)) = 12
	    THEN 'Декабрь'    
     END AS month_sold,
     total_area,
     ROUND(CAST(CAST(last_price AS NUMERIC)/ total_area AS NUMERIC),2) AS price_per_meter
     FROM cleared_data
     JOIN real_estate.flats AS flats
     ON cleared_data.id = flats.id
     JOIN real_estate.type ON flats.type_id = type.type_id
     WHERE type = 'город' ---фильтр по городу
     AND first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' ---исключаем 2014 и 2019 годы с неполными данными
     
),
--Вычисляем статистику по опубликованным объявлениям, здесь же можно посчитать среднюю площадь недвижимости и среднюю стоимость за метр.
calculation_by_published AS(
     SELECT
         month_published,
         first_day_exposition_month_number,
         COUNT(id) AS published_count,
         ROUND(CAST(avg(total_area) AS NUMERIC),2) AS avg_total_area,
         ROUND(CAST(avg(price_per_meter) AS NUMERIC),2) AS avg_price_per_meter
     FROM data_for_calculation
     GROUP BY 
         month_published,
         first_day_exposition_month_number
     ORDER BY first_day_exposition_month_number ASC
),
--Вычисляем статистику по снятым с публикации объявлениям, убирая из расчета значения, где отсуствует информация по дате снятия объявления.
calculation_by_sold AS(
     SELECT 
         month_sold,
         COUNT(id) AS sold_count
     FROM data_for_calculation
     WHERE month_sold IS NOT NULL
    GROUP BY 
         month_sold, 
         last_day_exposition_month_number
    ORDER BY last_day_exposition_month_number ASC
)
--Соединяем резульататы предыдущих запросов, выполняем ранжирование по активности для опубликованных и снятых объявлений.
SELECT
    month_published AS reposting_month,
    avg_price_per_meter,
    avg_total_area,
    published_count,
    sold_count,
    CASE 
	  WHEN NTILE(2) OVER(ORDER BY published_count DESC) = 1
	   THEN 'Высокая активность'
	  ELSE 'Низкая активность'
    END AS rank_published,
    CASE
	  WHEN NTILE(2) over(ORDER BY sold_count DESC) = 1
	   THEN 'Высокая активность'
	  ELSE 'Низкая активность'
    END AS sold_rank
FROM calculation_by_published
JOIN calculation_by_sold
ON calculation_by_published.month_published = calculation_by_sold.month_sold
ORDER BY first_day_exposition_month_number ASC;

-----Задача 3.  Анализ рынка недвижимости Ленобласти
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Вывод id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Формирование таблицы flats из схемы real_estate без аномалий:
flats AS(
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id)
),
-- СТЕ с показателями для последующих расчетов
cleaned_table AS(
SELECT
	a.last_price / f.total_area AS price_per_meter,
	f.total_area,
	c.city,
	a.first_day_exposition,
	a.days_exposition
FROM flats f 
LEFT JOIN real_estate.advertisement a USING(id)
LEFT JOIN real_estate.city c USING(city_id)
WHERE c.city <> 'Санкт-Петербург' -- фильтр на Лен. область согласно ТЗ
),
-- СТЕ с расчетами
stats AS(
SELECT 
	city,
	COUNT(first_day_exposition) AS total_exposition,
	ROUND(COUNT(days_exposition)::NUMERIC / COUNT(first_day_exposition) * 100, 2) AS sales_perc,
	ROUND(AVG(price_per_meter::NUMERIC), 2) AS avg_price_per_meter,
	ROUND(AVG(total_area::NUMERIC), 2) AS avg_area,
	ROUND(AVG(days_exposition::NUMERIC), 2) AS sales_speed
FROM cleaned_table
GROUP BY 1
HAVING COUNT(first_day_exposition) > 50 -- оставляю только те пункты, в которых публиковалось более 50 объявлений, тк пункты с меньшим числом не дают сделать объективные выводы
ORDER BY 3 DESC
LIMIT 15 -- составил ТОП 15 населенных пунктов согласно уточнениям у заказчика
)
-- Вывод итоговой таблицы
SELECT *
FROM stats;
