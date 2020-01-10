/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SLI_Rpt_WinLossByBettype_Member]
	@CustId			INT
	,@FromDate		SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductIds	VARCHAR(MAX) = '3'
	,@BalanceUpDay	SMALLDATETIME
	,@MoveBetsDay	SMALLDATETIME
AS

/*
	Created: 20200110@Percy
	Task: U3 - Report - Member Win Loss By Bet Type
	DB: DBAGE.bodb02

	Revisions:
		- 20200110@Percy: Initialize SP [RedmineID: #123584]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	SELECT @ProductIds = dbo.f_AddRelatedProducts(@ProductIds)

	-- get data
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #MemberWinLoss
		(
			SportType		SMALLINT
			,BetType		SMALLINT
			,LiveIndicator	BIT
			,BetCount		INT
			,TurnOver		MONEY
			,MemberWinLoss	MONEY
			,AgentWinLoss	MONEY
		)

		CREATE TABLE #tmpBettrans
		(
			MatchId			INT
			,BetType		SMALLINT
			,LiveIndicator	BIT
			,BetCount		INT
			,TurnOver		MONEY
			,MemberWinLoss	MONEY
			,AgentWinLoss	MONEY
		)

		-- bettrans
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate	= CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate

			INSERT INTO #tmpBettrans
			(
				MatchId
				,BetType
				,LiveIndicator
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
			)
			SELECT
				MatchId			= b.matchid
				,BetType		= b.bettype
				,LiveIndicator	= b.liveindicator
				,BetCount		= COUNT(1)
				,TurnOver		= SUM(ABS(b.stake))
				,MemberWinLoss	= SUM(b.winlost - b.actual_stake + b.playercomm)
				,AgentWinLoss	= SUM(b.awinlost + b.comm - b.playercomm)
			FROM dbo.bettrans b WITH (NOLOCK)
			WHERE b.recommend = @CustId
				AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusId IN (111, 112, 113)
				AND EXISTS (SELECT 1 FROM dbo.f_SportBettypeMatrixByProduct_Sel(@ProductIds, @IsTest) bt WHERE b.bettype = bt.bettype)
			GROUP BY
				b.matchid
				,b.bettype
				,b.liveindicator

			INSERT INTO #MemberWinLoss
			(
				SportType
				,BetType
				,LiveIndicator
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
			)
			SELECT
				SportType		= m.SportType
				,BetType		= b.BetType
				,LiveIndicator	= b.liveindicator
				,BetCount		= SUM(b.BetCount)
				,TurnOver		= SUM(b.TurnOver)
				,MemberWinLoss	= SUM(b.MemberWinLoss)
				,AgentWinLoss	= SUM(b.AgentWinLoss)
			FROM #tmpBettrans b
				CROSS APPLY (
					SELECT SportType FROM dbo.match m WITH (NOLOCK) WHERE b.matchid = m.matchid
				) m
			GROUP BY
				m.SportType
				,b.BetType
				,b.liveindicator
		END

		-- bettrans14
		IF @FromDate <= @MoveBetsDay
		BEGIN
			SELECT	@FDate	= CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
					,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			INSERT INTO #tmpBettrans
			(
				MatchId
				,BetType
				,LiveIndicator
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
			)
			SELECT
				MatchId			= b.matchid
				,BetType		= b.bettype
				,LiveIndicator	= b.liveindicator
				,BetCount		= COUNT(1)
				,TurnOver		= SUM(ABS(b.stake))
				,MemberWinLoss	= SUM(b.winlost - b.actual_stake + b.playercomm)
				,AgentWinLoss	= SUM(b.awinlost + b.comm - b.playercomm)
			FROM dbo.bettrans14 b WITH (NOLOCK)
			WHERE b.recommend = @CustId
				AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusId IN (111, 112, 113)
				AND EXISTS (SELECT 1 FROM dbo.f_SportBettypeMatrixByProduct_Sel(@ProductIds, @IsTest) bt WHERE b.bettype = bt.bettype)
			GROUP BY
				b.matchid
				,b.bettype
				,b.liveindicator

			INSERT INTO #MemberWinLoss
			(
				SportType
				,BetType
				,LiveIndicator
				,BetCount
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
			)
			SELECT
				SportType		= m.SportType
				,BetType		= b.BetType
				,LiveIndicator	= b.liveindicator
				,BetCount		= SUM(b.BetCount)
				,TurnOver		= SUM(b.TurnOver)
				,MemberWinLoss	= SUM(b.MemberWinLoss)
				,AgentWinLoss	= SUM(b.AgentWinLoss)
			FROM #tmpBettrans b
				CROSS APPLY (
					SELECT SportType FROM dbo.match14 m WITH (NOLOCK) WHERE b.matchid = m.matchid
				) m
			GROUP BY
				m.SportType
				,b.BetType
				,b.liveindicator
		END
	END

	DROP TABLE #tmpBettrans

	-- Return result
	BEGIN
		SELECT
			SportType		= SportType
			,BetType		= BetType
			,LiveIndicator	= LiveIndicator
			,BetCount		= SUM(BetCount)
			,TurnOver		= SUM(TurnOver)
			,MemberWinLoss	= SUM(MemberWinLoss)
			,AgentWinLoss	= SUM(AgentWinLoss)
		FROM #MemberWinLoss
		GROUP BY
			SportType
			,BetType
			,LiveIndicator
	END

	DROP TABLE #MemberWinLoss
END
GO