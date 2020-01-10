/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SLI_Rpt_WinLossDetail_Agent]
	@CustId			INT
	,@FromDate		SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductIds	VARCHAR(MAX) = '3'
	,@BalanceUpDay	SMALLDATETIME
	,@MoveBetsDay	SMALLDATETIME
	,@PageSize		INT = 0
	,@PageIndex		INT = 0
	,@TotalRecords	INT = 0 OUTPUT
AS

/*
	Created: 20200110@Percy
	Task: U3 - Report - Agent Win Loss Detail
	DB: DBAGE.bodb02

	Revisions:
		- 20200110@Percy: Initialize SP [RedmineID: #123584]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	SELECT @ProductIds = dbo.f_AddRelatedProducts(@ProductIds)

	DECLARE @RowStart	INT
			,@RowEnd	INT
		
	SELECT	@PageIndex	= @PageIndex - 1
			,@RowStart	= @PageSize * @PageIndex + 1
			,@RowEnd	= @RowStart + @PageSize - 1

	-- Get data
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #AgentWinLoss
		(
			CustId			INT
			,BetCount		INT
			,TurnOver		MONEY
			,MemberWinLoss	MONEY
			,AgentWinLoss	MONEY
			,MasterWinLoss	MONEY
		)

		-- bettrans
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate	= CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate

			INSERT INTO #AgentWinLoss
			(
				CustId
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
				,MasterWinLoss
			)
			SELECT
				CustId			= b.recommend
				,BetCount		= COUNT(1)
				,TurnOver		= SUM(ABS(b.stake))
				,MemberWinLoss	= SUM(b.winlost - b.actual_stake + b.playercomm)
				,AgentWinLoss	= SUM(b.awinlost + b.comm - b.playercomm)
				,MasterWinLoss	= SUM(b.mwinlost + b.acomm - b.comm)
			FROM dbo.bettrans b WITH (NOLOCK)
			WHERE b.mrecommend = @CustId
				AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusId IN (111, 112, 113)
				AND EXISTS (SELECT 1 FROM dbo.f_SportBettypeMatrixByProduct_Sel(@ProductIds, @IsTest) bt WHERE b.bettype = bt.bettype)
			GROUP BY
				b.recommend
		END

		-- sum_winloss & sum_winloss_old
		IF @FromDate <= @MoveBetsDay
		BEGIN
			CREATE TABLE #tblSportBettype (sporttype SMALLINT, bettype SMALLINT)

			INSERT INTO #tblSportBettype (sporttype, bettype)
			SELECT sporttype, bettype FROM dbo.f_SumWinloss_ConditionSel(@ProductIds)

			-- sum_winloss
			IF @ToDate >= @BalanceUpDay
			BEGIN
				SELECT	@FDate	= CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
						,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

				;WITH CTE_Winlostdate (winlostdate, sporttype, bettype) AS
				(
					SELECT @FDate AS winlostdate, sporttype, bettype
					FROM #tblSportBettype
					UNION ALL
					SELECT DATEADD(DAY, 1, winlostdate), sporttype, bettype
					FROM CTE_Winlostdate
					WHERE winlostdate < @TDate
				)
				INSERT INTO #AgentWinLoss
				(
					CustId
					,BetCount
					,TurnOver
					,MemberWinLoss
					,AgentWinLoss
					,MasterWinLoss
				)
				SELECT
					CustId			= s.custid
					,BetCount		= SUM(s.BetCount)
					,TurnOver		= SUM(s.TurnOver)
					,MemberWinLoss	= SUM(s.winlost + s.playercomm)
					,AgentWinLoss	= SUM(s.awinlost + s.comm - s.playercomm)
					,MasterWinLoss	= SUM(s.mwinlost + s.acomm - s.comm)
				FROM dbo.sum_winloss s WITH (NOLOCK)
					CROSS APPLY CTE_Winlostdate wld
				WHERE s.mrecommend = @CustId
					AND s.winlostdate = wld.winlostdate
					AND s.roleid = 2
					AND s.sporttype = wld.sporttype
					AND s.bettype = wld.bettype
				GROUP BY
					s.custid
				OPTION (MAXRECURSION 0)
			END

			-- sum_winloss_old
			IF @FromDate < @BalanceUpDay
			BEGIN
				SELECT	@FDate	= @FromDate
						,@TDate = CASE WHEN @ToDate >= @BalanceUpDay THEN DATEADD(DAY, -1, @BalanceUpDay) ELSE @ToDate END

				DECLARE @srecommend INT, @n INT
				SELECT  @srecommend = srecommend, @n = 1 FROM dbo.Customer WITH (NOLOCK) WHERE custid = @CustId

				;WITH CTE_Winlostdate (winlostdate, sporttype, bettype) AS
				(
					SELECT @FDate AS winlostdate, sporttype, bettype
					FROM #tblSportBettype
					UNION ALL
					SELECT DATEADD(DAY, 1, winlostdate), sporttype, bettype
					FROM CTE_Winlostdate
					WHERE winlostdate < @TDate
				)
				INSERT INTO #AgentWinLoss
				(
					CustId
					,BetCount
					,TurnOver
					,MemberWinLoss
					,AgentWinLoss
					,MasterWinLoss
				)
				SELECT
					CustId			= s.custid
					,BetCount		= SUM(s.BetCount)
					,TurnOver		= SUM(s.TurnOver)
					,MemberWinLoss	= SUM(s.winlost + s.playercomm)
					,AgentWinLoss	= SUM(s.awinlost + s.comm - s.playercomm)
					,MasterWinLoss	= SUM(s.mwinlost + s.acomm - s.comm)
				FROM bodb_Summary.dbo.sum_winloss_old s WITH (NOLOCK)
					CROSS APPLY CTE_Winlostdate wld
				WHERE	s.srecommend = @srecommend
					AND s.mrecommend = @CustId
					AND s.recommend = s.recommend * @n
					AND s.winlostdate = wld.winlostdate
					AND s.roleid = 2
					AND s.sporttype = wld.sporttype
					AND s.bettype = wld.bettype
				GROUP BY
					s.custid
				OPTION (MAXRECURSION 0)
			END

			DROP TABLE #tblSportBettype
		END
	END

	-- Return result
	BEGIN
		SELECT @TotalRecords = COUNT(DISTINCT CustId) FROM #AgentWinLoss

		-- Detail
		IF (@PageSize <= 0 AND @PageIndex <= 0) -- export excel
		BEGIN
			SELECT
				c.CustId
				,c.UserName
				,s.BetCount
				,s.TurnOver
				,s.MemberWinLoss
				,s.AgentWinLoss
				,s.MasterWinLoss
			FROM dbo.Customer c WITH (NOLOCK)
				INNER JOIN (
					SELECT
						CustId			= CustId
						,BetCount		= SUM(BetCount)
						,TurnOver		= SUM(TurnOver)
						,MemberWinLoss	= SUM(MemberWinLoss)
						,AgentWinLoss	= SUM(AgentWinLoss)
						,MasterWinLoss	= SUM(MasterWinLoss)
					FROM #AgentWinLoss
					GROUP BY
						CustId
				) s ON c.custid = s.CustId
			ORDER BY c.UserName
		END
		ELSE
		BEGIN
			SELECT
				CustId
				,UserName
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
				,MasterWinLoss
			FROM (
				SELECT
					c.CustId
					,c.UserName
					,s.BetCount
					,s.TurnOver
					,s.MemberWinLoss
					,s.AgentWinLoss
					,s.MasterWinLoss
					,ROW_NUMBER() OVER(ORDER BY c.UserName) AS RowNum
				FROM dbo.Customer c WITH (NOLOCK)
					INNER JOIN (
						SELECT
							CustId			= CustId
							,BetCount		= SUM(BetCount)
							,TurnOver		= SUM(TurnOver)
							,MemberWinLoss	= SUM(MemberWinLoss)
							,AgentWinLoss	= SUM(AgentWinLoss)
							,MasterWinLoss	= SUM(MasterWinLoss)
						FROM #AgentWinLoss
						GROUP BY
							CustId
					) s ON c.custid = s.CustId
			) r
			WHERE r.RowNum BETWEEN @RowStart AND @RowEnd
			ORDER BY RowNum
		END

		-- Total
		SELECT
			Betcount		= SUM(Betcount)
			,TurnOver		= SUM(TurnOver)
			,MemberWinLoss	= SUM(MemberWinLoss)
			,AgentWinLoss	= SUM(AgentWinLoss)
			,MasterWinLoss	= SUM(MasterWinLoss)
		FROM #AgentWinLoss
	END

	DROP TABLE #AgentWinLoss
END
GO