/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: 
 * Дата: 
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Напишите ваш запрос здесь
SELECT COUNT(id) AS total_players, ------Кол-во игроков, зарегистрированных в игре 
       SUM(payer) AS payer_players, ------Кол-во платящих игроков
       ROUND(AVG(payer :: numeric), 3) AS share_payers ------Доля плятящих пользователей
FROM fantasy.users u; 

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- Напишите ваш запрос здесь
SELECT r.race, 
      SUM(u.payer) AS pay_players, -------Кол-во платящих игроков в разрезе каждой рассы
      COUNT(u.id) AS total_players, ------Кол-во игроков, зарегистрированных в игре в разрезе каждой рассы
      ROUND(AVG(u.payer :: numeric), 3) AS share_payers ------ Доля платящих пользователей в разрезе расы персонажа
FROM fantasy.users AS u
JOIN fantasy.race AS r ON u.race_id = r.race_id
GROUP BY r.race;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Напишите ваш запрос здесь
SELECT COUNT(*) AS purchase_count, -----Общее кол-во покупок
       SUM(amount) AS total_amount,-----Общая стоимость всех покупок
       MIN(amount) AS min_amount, ----- Минимальная стоимость покупки
       MAX(amount) AS max_amount,----- Максимальная стоимость покупки
       ROUND(AVG(amount :: numeric),2) AS avg_amount, ----- Средняя стоимость покупки
       PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS median, ----- Медиана
      ROUND(STDDEV(amount :: NUMERIC), 2) AS stav_amount ----- Стандартное отклонение
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
-- Напишите ваш запрос здесь
--Проверяем существуют ли покупки с нулевой стоимостью:
SELECT *
FROM fantasy.events 
WHERE amount = 0;

--записи существуют, значит рассчитываем общее количество числа нулевых покупок:
WITH count_events AS (
	SELECT
	*,
	COUNT(*) OVER() AS count_transaction--общее количество покупок;
	FROM fantasy.events),
count_zero_events AS (
	SELECT 
	count_transaction,--общее количество покупок
	COUNT(*) AS count_zero_transaction --количество нулевых покупок
	FROM count_events 
	WHERE amount = 0
	GROUP BY count_transaction
)
SELECT 
	count_transaction,--общее количество покупок
	count_zero_transaction,--количество нулевых покупок
	ROUND(count_zero_transaction::NUMERIC/count_transaction::NUMERIC,3) AS fraction_zero_transaction --доля нулевых покупок от общего числа покупок
FROM count_zero_events;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
-- Напишите ваш запрос здесь
WITH 
cte AS (
	SELECT
		e.id,
		u.payer, 									  					 -- группа игрока: платящий/неплатящий
		COUNT(amount) AS total_purchase_per_user, 	 					 -- общее кол-во покупок на игрока
		SUM(amount) AS total_amount_per_user							 -- сумма всех покупок на уникального игрока
	FROM 
		fantasy.events AS e 
	JOIN 
		fantasy.users AS u ON u.id=e.id 
	WHERE 
		amount <> 0 												     -- исключаем покупки с нулевой стоимостью
	GROUP BY 
		payer, e.id  
	)
SELECT
	CASE
		WHEN payer = 0
			THEN 'неплатящий'
		WHEN payer = 1
			THEN 'платящий'
	END AS payer_type, 														   -- группа игроков: платящий/неплатящий
	COUNT(id) AS total_users,                 					               -- общее кол-во игроков
	SUM(total_purchase_per_user) AS total_purchase,  					       -- кол-во покупок
	ROUND(SUM(total_purchase_per_user)::NUMERIC / COUNT(id)) AS avg_purchase,  -- ср.кол-во покупок на игрока
	ROUND(SUM(total_amount_per_user)::NUMERIC / COUNT(user),2) AS avg_amount   -- ср.ст-ть покупки на игрока
FROM 
	cte
GROUP BY 
	payer;

-- 2.4: Популярные эпические предметы:
-- Напишите ваш запрос здесь
WITH item_stats AS (
  SELECT 
    i.game_items, 
    i.item_code, 
    COUNT(e.transaction_id) AS total_sales, ----Общее кол-во покупок предмета
    COUNT(DISTINCT e.id) AS unique_users   -----Кол-во уникальных пользователей, купивших предмет
  FROM fantasy.items i
  LEFT JOIN fantasy.events e ON e.item_code = i.item_code 
  WHERE e.amount != 0
  GROUP BY i.game_items, i.item_code)

SELECT 
  game_items, 
  total_sales, 
  ROUND(total_sales * 1.0 / SUM(total_sales) OVER (), 2) AS share_sales_item, -----Доля продажи каждого предмета от всех продаж
  ROUND(unique_users * 1.0 / (
    SELECT COUNT(DISTINCT id) 
    FROM fantasy.events
  ), 2) AS share_users ------Доля игроков, купивших предмет
FROM item_stats
ORDER BY share_users DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
-- Напишите ваш запрос здесь
--Количество пользователей для каждой расы
WITH users as(
SELECT race,
	   r.race_id,
	   COUNT(u.id) AS users_count
FROM fantasy.users u 
LEFT JOIN fantasy.race r ON u.race_id = r.race_id
GROUP BY race, r.race_id),
--Количество и доля игроков, совершивших покупку
buyers AS (
SELECT race,
	   r.race_id,
	   COUNT(DISTINCT e.id) AS buyers_count,
	   ROUND(COUNT(DISTINCT e.id)::numeric/count(u.id), 3) AS buyers_share
FROM fantasy.users u 
LEFT JOIN fantasy.race r ON u.race_id = r.race_id
LEFT JOIN fantasy.events e ON u.id = e.id
WHERE amount > 0
GROUP BY race, r.race_id),
--Количество и доля платящих игроков
payers as(
SELECT race,
	   r.race_id,
	   COUNT(DISTINCT e.id) AS payers_count 
FROM fantasy.users u 
LEFT JOIN fantasy.race r ON u.race_id = r.race_id
LEFT JOIN fantasy.events e ON u.id = e.id
WHERE payer = 1 AND amount>0
GROUP BY race, r.race_id),
--Среднее количество покупок,средняя стоимость одной покупки, средняя суммарную стоимость всех покупок на одного игрока
stats  as(
SELECT race,
	   r.race_id,
	   ROUND(COUNT(transaction_id)/COUNT(DISTINCT e.id)::NUMERIC) AS avg_transactions_per_user,
	   ROUND(SUM(amount)::numeric/COUNT(transaction_id)) AS avg_one_purchace_amount,
	   ROUND(SUM(amount)::NUMERIC/COUNT(DISTINCT e.id)) AS avg_all_purchaces_amount
FROM fantasy.users u 
LEFT JOIN fantasy.race r ON u.race_id = r.race_id
LEFT JOIN fantasy.events e ON u.id = e.id
WHERE amount > 0
GROUP BY race, r.race_id)
--Основной запрос, считающий необходимые показатели
SELECT u.race_id,
	   u.race,
	   users_count,
	   buyers_count,
	   round(buyers_count/users_count::NUMERIC, 3) AS buyers_share,
	   round(payers_count::NUMERIC/buyers_count, 2) AS payers_share,
	   avg_transactions_per_user,
	   avg_one_purchace_amount,
	   avg_all_purchaces_amount
FROM users u
FULL JOIN buyers b ON u.race_id = b.race_id
FULL JOIN payers p ON u.race_id = p.race_id
FULL JOIN stats s ON s.race_id = u.race_id
ORDER BY buyers_share DESC, payers_Share DESC;

 -- Задача 2: Частота покупок
-- Напишите ваш запрос здесь