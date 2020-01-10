/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SLI_Rpt_WinlossAnalysis_Agent]
	@CustId			INT
	,@FromDate		SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductIds	VARCHAR(MAX) = '3'
	,@BalanceUpDay	SMALLDATETIME
	,@MoveBetsDay	SMALLDATETIME
	,@ReportType	TINYINT = 1
AS

/*
	Created: 20200110@Percy
	Task: U3 - Report - Agent Win Loss Analysis
	DB: DBAGE.bodb02

	Revisions:
		- 20200110@Percy: Initialize SP [RedmineID: #123584]

	Param's Explanation:
		@ReportType: 1 = Daily, 2 = Monthly, 3 = Sport
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	SELECT @ProductIds = dbo.f_AddRelatedProducts(@ProductIds)

	-- get data
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #AgentWinLoss
		(
			WinlostDate		SMALLDATETIME
			,SportType		SMALLINT
			,BetCount		INT
			,TurnOver		MONEY
			,MemberWinLoss	MONEY
			,AgentWinLoss	MONEY
			,MasterWinLoss	MONEY
		)

		-- bettrans
		IF @ToDate > @MoveBetsDay
		BEGIN
			CREATE TABLE #tmpBettrans
			(
				WinlostDate		SMALLDATETIME
				,MatchId		INT
				,BetCount		INT
				,TurnOver		MONEY
				,MemberWinLoss	MONEY
				,AgentWinLoss	MONEY
				,MasterWinLoss	MONEY
			)

			SELECT	@FDate	= CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate

			INSERT INTO #tmpBettrans
			(
				WinlostDate
				,MatchId
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
				,MasterWinLoss
			)
			SELECT
				WinlostDate		= CASE @ReportType WHEN 1 THEN DATEADD(DAY, 1, b.winlostdate) WHEN 2 THEN b.winlostdate END
				,MatchId		= CASE @ReportType WHEN 3 THEN b.matchid END
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
				CASE @ReportType WHEN 1 THEN DATEADD(DAY, 1, b.winlostdate) WHEN 2 THEN b.winlostdate END
				,CASE @ReportType WHEN 3 THEN b.matchid END

			IF @ReportType = 3
			BEGIN
				INSERT INTO #AgentWinLoss
				(
					SportType
					,BetCount
					,TurnOver
					,MemberWinLoss
					,AgentWinLoss
					,MasterWinLoss
				)
				SELECT
					SportType		= m.SportType
					,BetCount		= SUM(b.BetCount)
					,TurnOver		= SUM(b.TurnOver)
					,MemberWinLoss	= SUM(b.MemberWinLoss)
					,AgentWinLoss	= SUM(b.AgentWinLoss)
					,MasterWinLoss	= SUM(b.MasterWinLoss)
				FROM #tmpBettrans b
					CROSS APPLY (
						SELECT SportType FROM dbo.match m WITH (NOLOCK) WHERE b.matchid = m.matchid
					) m
				GROUP BY
					m.SportType
			END
			ELSE
			BEGIN
				INSERT INTO #AgentWinLoss
				(
					WinlostDate
					,BetCount
					,TurnOver
					,MemberWinLoss
					,AgentWinLoss
					,MasterWinLoss
				)
				SELECT
					SportType		= b.WinlostDate
					,BetCount		= SUM(b.BetCount)
					,TurnOver		= SUM(b.TurnOver)
					,MemberWinLoss	= SUM(b.MemberWinLoss)
					,AgentWinLoss	= SUM(b.AgentWinLoss)
					,MasterWinLoss	= SUM(b.MasterWinLoss)
				FROM #tmpBettrans b
				GROUP BY
					b.WinlostDate
			END

			DROP TABLE #tmpBettrans
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
					WinlostDate
					,SportType
					,BetCount
					,TurnOver
					,MemberWinLoss
					,AgentWinLoss
					,MasterWinLoss
				)
				SELECT
					WinlostDate		= s.winlostdate
					,SportType		= s.sporttype
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
					s.mrecommend
					,s.winlostdate
					,s.roleid
					,s.sporttype
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
					WinlostDate
					,SportType
					,BetCount
					,TurnOver
					,MemberWinLoss
					,AgentWinLoss
					,MasterWinLoss
				)
				SELECT
					WinlostDate		= s.winlostdate
					,SportType		= s.sporttype
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
					s.srecommend
					,s.mrecommend
					,s.recommend
					,s.winlostdate
					,s.roleid
					,s.sporttype
				OPTION (MAXRECURSION 0)
			END

			DROP TABLE #tblSportBettype
		END
	END

	-- Return result
	BEGIN
		SELECT
			RollupKey		= CASE @ReportType	WHEN 1 THEN CONVERT(VARCHAR(10), WinlostDate, 101)  
												WHEN 2 THEN RIGHT(CONVERT(VARCHAR(10), WinlostDate, 103), 7)  
												WHEN 3 THEN CONVERT(VARCHAR(10), SportType)
												ELSE '0' END
			,BetCount		= SUM(BetCount)
			,TurnOver		= SUM(TurnOver)
			,MemberWinLoss	= SUM(MemberWinLoss)
			,AgentWinLoss	= SUM(AgentWinLoss)
			,MasterWinLoss	= SUM(MasterWinLoss)
		FROM #AgentWinLoss
		GROUP BY
			CASE @ReportType	WHEN 1 THEN CONVERT(VARCHAR(10), WinlostDate, 101)  
								WHEN 2 THEN RIGHT(CONVERT(VARCHAR(10), WinlostDate, 103), 7)  
								WHEN 3 THEN CONVERT(VARCHAR(10), SportType)
								ELSE '0' END

		-- Total
		SELECT
			BetCount		= SUM(BetCount)
			,TurnOver		= SUM(TurnOver)
			,MemberWinLoss	= SUM(MemberWinLoss)
			,AgentWinLoss	= SUM(AgentWinLoss)
			,MasterWinLoss	= SUM(MasterWinLoss)
		FROM #AgentWinLoss
	END

	DROP TABLE #AgentWinLoss
END
GO