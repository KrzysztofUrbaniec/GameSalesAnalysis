/*
 * SQL queries for the analysis of game sales
 */

-- Add id column
ALTER TABLE game_sales 
ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY;

-- Remove duplicated rows
DELETE FROM game_sales WHERE id IN ( 
	SELECT id
	FROM (
	SELECT *,
		ROW_NUMBER() OVER (PARTITION BY Name, Platform, Developer, Year
		ORDER BY id) rn
	FROM
		game_sales gs) sq
	WHERE rn > 1
);

-- Yearly trends:
/*
 * Q1: How many games were sold each year (in millions of copies), regardless of the platform? 
 * Return: Year, Total Units Sold
 */

SELECT
	Year, 
	SUM(Total_shipped) as Total
FROM game_sales
GROUP BY Year
ORDER BY Year DESC;

/* 
 * What was the number of "good" games per year?
 * Q2: How many games with average (i.e. across different platforms) critic score >= 8.0 were released each year?
 * Return: Year, Num Games
*/

SELECT 
	sq.Year, 
	SUM(CASE WHEN sq.Avg_Score >= 8.0 THEN 1 ELSE 0 END) AS Num_Games
FROM (
	SELECT 
		gs.Name, 
		gs.Year, 
		AVG(gs.Critic_Score) AS Avg_Score
	FROM 
		game_sales gs 
	GROUP BY 
		Name, Year
	HAVING 
		Avg_Score IS NOT NULL ) sq
GROUP BY Year
ORDER BY Year DESC;

/*
 * We'd like to know if games are getting worse.  
 * Q3: How have the average critic score changed over the years for games released on PC? Filter the dataset, so it contains only years with more than 5 games.
 * Return: Year, Num Games, Avg Critic Score
 */

SELECT  
	gs.Year,
	COUNT(gs.Name) as Num_Games,
	ROUND(AVG(gs.Critic_Score),1) AS Avg_Critic_Score
FROM 
	game_sales gs 
WHERE gs.Platform = 'PC' AND gs.Critic_Score IS NOT NULL
GROUP BY Year
HAVING Num_Games > 5
ORDER BY Year DESC;

/*
 * Let's say, we'd like to learn more about Rockstar Games' performance. 
 * Q4: Let's calculate their market share in Xbox360 games using total units sold and analyze how it has changed over the years.
 * Return: Year, Market Share (%)
 */

-- Calculate the total sales per year + total sales per year AND publisher, then join the tables
SELECT 
	t1.Year,
	ROUND(Total_per_Publisher / Total_per_Year * 100,2) AS Market_Share
FROM
	(SELECT 
		Year,
		Publisher,
		SUM(Total_Shipped) as Total_per_Publisher
	FROM
		game_sales gs 
	WHERE
		Platform = 'X360'
	GROUP BY Year, Publisher) t1
JOIN 
	(SELECT 
		Year,
		SUM(Total_Shipped) as Total_per_Year
	FROM 
		game_sales gs2
	WHERE
		Platform = 'X360'
	GROUP BY Year) t2
ON t1.Year = t2.Year
WHERE 
	Publisher = 'Rockstar Games'
ORDER BY Year DESC;

-- Sales Perfomance:
/*
 * Q1: What are the most popular games of all time in terms of units sold?
 * Identify 10 most popular games.
 * Return: Game, Year, Publisher, Number of units sold (mln copies)
 */

SELECT 
	Name,
	Publisher,
	SUM(Total_Shipped) AS Total
FROM
	game_sales gs 
GROUP BY 
	Name, Publisher 
ORDER BY 
	Total DESC
LIMIT 10;

/*
 * Q2: How do average sales vary based on critic score?
 * Categorize the games into three distinct groups based on average critic score 
 * (low: critic score < 5.5, medium: 5.5 <= critic score <= 8.5, high: critic score > 8.5) and analyze the average sales in each group.
 * Return: Critic score group, Num Games, Avg Sales (mln copies)
 */

SELECT
	sq.Critic_Score_Category,
	COUNT(sq.Critic_Score_Category) AS Num_Games,
	ROUND(AVG(Total),2) AS Avg_Sales
FROM (
	SELECT 
		gs.Name, 
		CASE 
			WHEN AVG(gs.Critic_Score) < 5.5 THEN 'Low'
			WHEN AVG(gs.Critic_Score) >= 5.5 AND AVG(gs.Critic_Score) <= 8.5 THEN 'Medium'
			WHEN AVG(gs.Critic_Score) > 8.5 THEN 'High'
		END AS Critic_Score_Category,
		SUM(gs.Total_Shipped) AS Total
	FROM 
		game_sales gs 
	GROUP BY Name
	HAVING 
		Critic_Score_Category IS NOT NULL) sq
GROUP BY 
	sq.Critic_Score_Category
ORDER BY 
	FIELD(sq.Critic_Score_Category, 'High','Medium','Low');

/*
 * Earlier we were analyzing the market share of Rockstar Games in the segment of games for Xbox 360.
 * Q3: Now, let's identify the top 10% of Xbox 360 game publishers based on total sales from 2010 to 2018.
 * Return: Year, Publisher, Total sales
 */

WITH XBoxPublisherRankCTE AS (
	SELECT 
		sq.Year,
		sq.Publisher,
		sq.Total,
		PERCENT_RANK() OVER(PARTITION BY sq.Year ORDER BY sq.Total) AS PercRank
	FROM (
		SELECT 
			Year, 
			Publisher, 
			SUM(Total_Shipped) AS Total
		FROM
			game_sales gs
		WHERE 
			Platform = 'X360' AND (Year BETWEEN 2010 AND 2018)
		GROUP BY 
			Year, Publisher) sq
)
SELECT 
	Year, Publisher, Total
FROM 
	XBoxPublisherRankCTE
WHERE 	
	PercRank >= 0.9
ORDER BY 
	Year DESC, Total DESC;

-- Platform:
/*
 * Q1: What were the most popular games (in terms of units sold) per platform?
 * Identify 3 best-selling games of all times, allowing for ex-aequo places, for each platform and order them by units sold in descending order.
 * Return: Platform, Publisher, Games, Total Sales
 */

WITH PopularGamesPerPlatformCTE AS (
	SELECT 
		sq.Platform,
		sq.Name,
		sq.Publisher,
		sq.Total_Sales,
		DENSE_RANK() OVER(PARTITION BY Platform ORDER BY Total_Sales DESC) AS Rankk
	FROM (
		SELECT  
			Platform,
			Name,
			Publisher,
			SUM(Total_Shipped) AS Total_Sales
		FROM 
			game_sales gs 
		GROUP BY 
			Platform, Name, Publisher) sq
)
SELECT 
	Platform,
	Name,
	Publisher,
	Total_Sales
From 
	PopularGamesPerPlatformCTE
WHERE 
	Rankk <= 3
ORDER BY 
	Platform, Total_Sales DESC;

/*
 * Q2: How about games with the highest critic score per platform?
 * Identify 3 games with highest critic score, allowing for ex-aequo places, for each platform and order them by the score in descending order.
 * Return: Platform, Name, Publisher, Average Critic Score
 */

WITH GreatGamesPerPlatformCTE AS (
SELECT 
	sq.Platform,
	sq.Name,
	sq.Publisher,
	sq.Avg_CScore,
	DENSE_RANK() OVER(PARTITION BY Platform ORDER BY Avg_CScore DESC) AS Rankk
FROM (
	SELECT  
		gs.Platform,
		gs.Name,
		gs.Publisher,
		AVG(gs.Critic_Score) AS Avg_CScore
	FROM 
		game_sales gs 
	GROUP BY 
		gs.Platform, gs.Name, gs.Publisher
	HAVING 
		Avg_CScore IS NOT NULL
	) sq
)
SELECT 
	Platform,
	Name,
	Publisher,
	Avg_CScore
FROM 
	GreatGamesPerPlatformCTE
WHERE 
	Rankk <= 3 
ORDER BY 
	Platform, Avg_CScore DESC;
	
/*
 * Q3: What was the popularity of different platforms in past decades?
 * Calculate the total sales for each decade and divide platforms into three groups: PC, Console or Other
 * Return: Decade, Platform_type, Total
 */

SELECT 
    CASE 
        WHEN year BETWEEN 1980 AND 1989 THEN '1980s'
        WHEN year BETWEEN 1990 AND 1999 THEN '1990s'
        WHEN year BETWEEN 2000 AND 2009 THEN '2000s'
        WHEN year BETWEEN 2010 AND 2019 THEN '2010s'
        ELSE 'Other'
    END AS Decade,
    CASE 
        WHEN (gs.Platform LIKE 'PS%' OR gs.Platform IN ('X360', 'PSP', 'DS', 'Wii')) THEN 'Console'
        WHEN gs.Platform IN ('PC') THEN 'PC'
        ELSE 'Other'
    END AS Platform_type,
    ROUND(SUM(Total_Shipped),2) AS Total
FROM game_sales gs
GROUP BY Decade, Platform_type
ORDER BY Decade, Platform_type;

	
