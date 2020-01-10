/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO
ALTER PROCEDURE [dbo].[SLI_Rpt_MatchWinLossDetail_Master]
	@CustId			INT
	,@FromDate		SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductIds	VARCHAR(MAX) = '3'
	,@BalanceUpDay	SMALLDATETIME
	,@MoveBetsDay	SMALLDATETIME
AS

/*
	Created: 20200110@Percy
	Task: U3 - Report - Master Match Win Loss Detail
	DB: DBAGE.bodb02

	Revisions:
		- 20200110@Percy: Initialize SP [RedmineID: #123584]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	SELECT @ProductIds = dbo.f_AddRelatedProducts(@ProductIds)

	-- Get data
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #bettype (bettype SMALLINT)
		INSERT INTO #bettype (bettype)
		SELECT bettype FROM dbo.f_SportBettypeMatrixByProduct_Sel(@ProductIds, @IsTest)

		CREATE TABLE #MasterWinLoss
		(
			MatchId			INT
			,SportType		SMALLINT
			,HomeId			INT
			,AwayId			INT
			,LeagueId		INT
			,MatchCode		NVARCHAR(50)
			,BetType		SMALLINT
			,LiveIndicator	BIT
			,TurnOver		MONEY
			,MemberWinLoss	MONEY
			,AgentWinLoss	MONEY
			,MasterWinLoss	MONEY
			,SuperWinLoss	MONEY
			,RangeType		TINYINT -- 1: bettrans, 2: bettrans14
		)

		-- bettrans
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate	= CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate

			INSERT INTO #MasterWinLoss
			(
				MatchId
				,BetType
				,LiveIndicator
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
				,MasterWinLoss
				,SuperWinLoss
				,RangeType
			)
			SELECT
				MatchId			= b.matchid
				,BetType		= b.bettype
				,LiveIndicator	= b.liveindicator
				,TurnOver		= SUM(ABS(b.stake))
				,MemberWinLoss	= SUM(b.winlost - b.actual_stake + b.playercomm)
				,AgentWinLoss	= SUM(b.awinlost + b.comm - b.playercomm)
				,MasterWinLoss	= SUM(b.mwinlost + b.acomm - b.comm)
				,SuperWinLoss	= SUM(b.swinlost + b.scomm - b.acomm)
				,RangeType		= 1
			FROM dbo.bettrans b WITH (NOLOCK)
			WHERE b.srecommend = @CustId
				AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusId IN (111, 112, 113)
				AND EXISTS (SELECT 1 FROM #bettype bt WHERE b.bettype = bt.bettype)
			GROUP BY
				b.matchid
				,b.bettype
				,b.liveindicator
		END

		-- bettrans14
		IF @FromDate <= @MoveBetsDay
		BEGIN
			SELECT	@FDate	= CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
					,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			INSERT INTO #MasterWinLoss
			(
				MatchId
				,BetType
				,LiveIndicator
				,TurnOver
				,MemberWinLoss
				,AgentWinLoss
				,MasterWinLoss
				,SuperWinLoss
				,RangeType
			)
			SELECT
				MatchId			= b.matchid
				,BetType		= b.bettype
				,LiveIndicator	= b.liveindicator
				,TurnOver		= SUM(ABS(b.stake))
				,MemberWinLoss	= SUM(b.winlost - b.actual_stake + b.playercomm)
				,AgentWinLoss	= SUM(b.awinlost + b.comm - b.playercomm)
				,MasterWinLoss	= SUM(b.mwinlost + b.acomm - b.comm)
				,SuperWinLoss	= SUM(b.swinlost + b.scomm - b.acomm)
				,RangeType		= 2
			FROM dbo.bettrans14 b WITH (NOLOCK)
			WHERE b.srecommend = @CustId
				AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusId IN (111, 112, 113)
				AND EXISTS (SELECT 1 FROM #bettype bt WHERE b.bettype = bt.bettype)
			GROUP BY
				b.matchid
				,b.bettype
				,b.liveindicator
		END
	END

	-- Return result
	BEGIN
		IF EXISTS (SELECT 1 FROM #MasterWinLoss WHERE RangeType = 1)
			UPDATE a
			SET a.SportType = m.SportType, a.HomeId = m.HomeId, a.AwayId = m.AwayId, a.LeagueId = m.LeagueId, a.MatchCode = m.MatchCode
			FROM #MasterWinLoss a
				INNER JOIN dbo.match m WITH (NOLOCK) ON a.MatchId = m.MatchId
			WHERE a.RangeType = 1
		
		IF EXISTS (SELECT 1 FROM #MasterWinLoss WHERE RangeType = 2)
			UPDATE a
			SET a.SportType = m.SportType, a.HomeId = m.HomeId, a.AwayId = m.AwayId, a.LeagueId = m.LeagueId, a.MatchCode = m.MatchCode
			FROM #MasterWinLoss a
				INNER JOIN dbo.match14 m WITH (NOLOCK) ON a.MatchId = m.MatchId
			WHERE a.RangeType = 2

		SELECT
			MatchId
			,SportType
			,HomeId
			,AwayId
			,LeagueId
			,MatchCode
			,BetType
			,LiveIndicator
			,TurnOver
			,MemberWinLoss
			,AgentWinLoss
			,MasterWinLoss
			,SuperWinLoss
		FROM #MasterWinLoss
		WHERE SportType IS NOT NULL
	END

	DROP TABLE #MasterWinLoss
	DROP TABLE #bettype
END
GO