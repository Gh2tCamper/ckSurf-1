
//
// Botmimic2 - modified by 1NutWunDeR
// http://forums.alliedmods.net/showthread.php?t=164148
//
void setReplayTime(int zGrp)
{
	char sPath[256], sTime[54], sBuffer[4][54];
	if (zGrp > 0)
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, zGrp);
	else
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);

	FileHeader iFileHeader;
	LoadRecordFromFile(sPath, iFileHeader);
	Format(sTime, sizeof(sTime), "%s", iFileHeader.FH_Time);

	ExplodeString(sTime, ":", sBuffer, 4, 54);
	float time = (StringToFloat(sBuffer[0]) * 60);
	time += StringToFloat(sBuffer[1]);
	time += (StringToFloat(sBuffer[2]) / 100);
	if (zGrp == 0)
	{
		if ((g_fRecordMapTime - 0.01) < time < (g_fRecordMapTime) + 0.01)
			time = g_fRecordMapTime;
	}
	else
	{
		if ((g_fBonusFastest[zGrp] - 0.01) < time < (g_fBonusFastest[zGrp]) + 0.01)
			time = g_fBonusFastest[zGrp];
	}

	g_fReplayTimes[zGrp] = time;
}

public Action RespawnBot(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client)
		return Plugin_Stop;

	if (g_hBotMimicsRecord[client] != null && IsValidClient(client) && !IsPlayerAlive(client) && IsFakeClient(client) && GetClientTeam(client) >= CS_TEAM_T)
	{
		TeamChangeActual(client, 2);
		CS_RespawnPlayer(client);
	}

	return Plugin_Stop;
}

public Action Hook_WeaponCanSwitchTo(int client, int weapon)
{
	if (g_hBotMimicsRecord[client] == null)
		return Plugin_Continue;

	if (g_BotActiveWeapon[client] != weapon)
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void StartRecording(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	g_hRecording[client] = CreateArray(sizeof(FrameInfo));
	g_hRecordingAdditionalTeleport[client] = CreateArray(sizeof(AdditionalTeleport));
	GetClientAbsOrigin(client, g_fInitialPosition[client]);
	GetClientEyeAngles(client, g_fInitialAngles[client]);
	g_RecordedTicks[client] = 0;
	g_OriginSnapshotInterval[client] = 0;
}

public void StopRecording(int client)
{
	if (!IsValidClient(client) || g_hRecording[client] == null)
		return;

	CloseHandle(g_hRecording[client]);
	CloseHandle(g_hRecordingAdditionalTeleport[client]);
	g_hRecording[client] = null;
	g_hRecordingAdditionalTeleport[client] = null;

	g_RecordedTicks[client] = 0;
	g_RecordPreviousWeapon[client] = 0;
	g_CurrentAdditionalTeleportIndex[client] = 0;
	g_OriginSnapshotInterval[client] = 0;
}

public void SaveRecording(int client, int zgroup)
{
	if (!IsValidClient(client) || g_hRecording[client] == null) {
		g_bNewReplay[client] = false;
		g_bNewBonus[client] = false;
		return;
	}
	

	char sPath2[256];
	// Check if the default record folder exists?
	BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s", CK_REPLAY_PATH);
	if (!DirExists(sPath2))
	{
		CreateDirectory(sPath2, 511);
	}

	if (zgroup == 0) // replay bot
	{
		BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
	}
	else
	{
		if (zgroup > 0) // bonus bot
		{
			BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, zgroup);
		}
	}

	if (FileExists(sPath2) && GetConVarBool(g_hBackupReplays))
	{
		char newPath[256];
		Format(newPath, 256, "%s.bak", sPath2);
		RenameFile(newPath, sPath2);
	}

	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);

	FileHeader iHeader;
	iHeader.FH_binaryFormatVersion = BINARY_FORMAT_VERSION;
	strcopy(iHeader.FH_Time, 32, g_szFinalTime[client]);
	iHeader.FH_tickCount = GetArraySize(g_hRecording[client]);
	strcopy(iHeader.FH_Playername, 32, szName);
	iHeader.FH_Checkpoints = 0; // So that KZTimers replays work
	Array_Copy(g_fInitialPosition[client], iHeader.FH_initialPosition, 3);
	Array_Copy(g_fInitialAngles[client], iHeader.FH_initialAngles, 3);
	iHeader.FH_frames = g_hRecording[client];

	if (GetArraySize(g_hRecordingAdditionalTeleport[client]) > 0)
		SetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath2, g_hRecordingAdditionalTeleport[client]);
	else
	{
		CloseHandle(g_hRecordingAdditionalTeleport[client]);
		g_hRecordingAdditionalTeleport[client] = null;
	}

	WriteRecordToDisk(sPath2, iHeader);

	g_bNewReplay[client] = false;
	g_bNewBonus[client] = false;

	if (g_hRecording[client] != null)
		StopRecording(client);
}


public void LoadReplays()
{
	if (!GetConVarBool(g_hReplayBot))
		return;

	// Init variables:
	g_bMapReplay = true;

	for (int i = 0; i < MAXZONEGROUPS; i++)
	{
		g_fReplayTimes[i] = 0.0;
		g_bMapBonusReplay[i] = false;
	}

	g_bIsPlayingReplay = false;
	g_CurrentReplay = -1;
	g_ReplayRequester = 0;
	g_BonusBotCount = 0;
	g_RecordBot = -1;
	g_ReplayCurrentStage = 0;
	ClearTrie(g_hLoadedRecordsAdditionalTeleport);

	// Check that map replay exists
	char sPath[256];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
	if (FileExists(sPath))
	{
		setReplayTime(0);
		g_bMapReplay = true;
	}
	else// Check if backup exists
	{
		char sPathBack[256];
		BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s.rec.bak", CK_REPLAY_PATH, g_szMapName);
		if (FileExists(sPathBack))
		{
			RenameFile(sPath, sPathBack);
			setReplayTime(0);
			g_bMapReplay = true;
		}
	}

	// Try to fix old bonus replays
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_Bonus.rec", CK_REPLAY_PATH, g_szMapName);
	Handle hFilex = OpenFile(sPath, "r");

	if (hFilex != null)
	{
		FileHeader iFileHeader;
		float initPos[3];
		char newPath[256];
		LoadRecordFromFile(sPath, iFileHeader);
		Array_Copy(iFileHeader.FH_initialPosition, initPos, 3);
		int zId = IsInsideZone(initPos, 50.0);
		if (zId != -1 && g_mapZones[zId].zoneGroup != 0)
		{
			BuildPath(Path_SM, newPath, sizeof(newPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, g_mapZones[zId].zoneGroup);
			if (RenameFile(newPath, sPath))
				PrintToServer("[Surf Timer] Succesfully renamed bonus record file to: %s", newPath);
		}
		CloseHandle(hFilex);
	}
	hFilex = null;

	// Check if bonus replays exists
	for (int i = 1; i < g_mapZoneGroupCount; i++)
	{
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, i);
		if (FileExists(sPath))
		{
			setReplayTime(i);
			g_iBonusToReplay[g_BonusBotCount] = i;
			g_BonusBotCount++;
			g_bMapBonusReplay[i] = true;
		}
		else// Check if backup exists
		{
			char sPathBack[256];
			BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_bonus_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, i);
			if (FileExists(sPathBack))
			{
				setReplayTime(i);
				RenameFile(sPath, sPathBack);
				g_iBonusToReplay[g_BonusBotCount] = i;
				g_BonusBotCount++;
				g_bMapBonusReplay[i] = true;
			}
		}
	}

	CreateTimer(1.0, RefreshBot, TIMER_FLAG_NO_MAPCHANGE);
}

public void PlayRecord(int client, char[] id)
{
	if (!IsValidClient(client))
		return;
	char buffer[256];
	char sPath[256];
	int type = StringToInt(id);

	if (type == 0)
		Format(sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
	if (type > 0)
		Format(sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, type);
	if (type < 0) {
		Format(sPath, sizeof(sPath), "%s%s_stage_%i.rec", CK_REPLAY_PATH, g_szMapName, (type * -1));
		g_ReplayCurrentStage = type * -1;
	}


	// He's currently recording. Don't start to play some record on him at the same time.
	if (g_hRecording[client] != null || !IsFakeClient(client))
		return;

	FileHeader iFileHeader;
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", sPath);

	if (!FileExists(sPath))
	{
		PrintToChat(g_ReplayRequester, "[%cSurf Timer%c] %cReplay not found.", MOSSGREEN, WHITE, YELLOW);
		g_ReplayRequester = -1;
		return;
	}

	LoadRecordFromFile(sPath, iFileHeader);

	if (type == 0)
	{
		Format(g_szReplayTime, sizeof(g_szReplayTime), "%s", iFileHeader.FH_Time);
		Format(g_szReplayName, sizeof(g_szReplayName), "%s", iFileHeader.FH_Playername);
		Format(buffer, sizeof(buffer), "%s (%s)", g_szReplayName, g_szReplayTime);
		SetClientName(client, buffer);
	}
	else if (type > 0)
	{
		Format(g_szBonusTime, sizeof(g_szBonusTime), "%s", iFileHeader.FH_Time);
		Format(g_szBonusName, sizeof(g_szBonusName), "%s", iFileHeader.FH_Playername);
		Format(buffer, sizeof(buffer), "%s (%s)", g_szBonusName, g_szBonusTime);
		SetClientName(client, buffer);
	}
	else if (type < 0)
	{
		Format(buffer, sizeof(buffer), "%s (%s)", iFileHeader.FH_Playername, iFileHeader.FH_Time);
		SetClientName(client, buffer);
	}

	g_hBotMimicsRecord[client] = iFileHeader.FH_frames;
	g_BotMimicTick[client] = 0;
	g_BotMimicRecordTickCount[client] = iFileHeader.FH_tickCount;
	g_CurrentAdditionalTeleportIndex[client] = 0;

	Array_Copy(iFileHeader.FH_initialPosition, g_fInitialPosition[client], 3);
	Array_Copy(iFileHeader.FH_initialAngles, g_fInitialAngles[client], 3);
	SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
	// Respawn him to get him moving!
	if (IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= CS_TEAM_T)
	{
		CS_RespawnPlayer(client);
		if (GetConVarBool(g_hForceCT))
			TeamChangeActual(client, 2);
	}

	g_bIsPlayingReplay = true;
}

public void WriteRecordToDisk(const char[] sPath, FileHeader iFileHeader)
{
	Handle hFile = OpenFile(sPath, "wb");
	if (hFile == null)
	{
		LogError("Can't open the record file for writing! (%s)", sPath);
		return;
	}

	WriteFileCell(hFile, BM_MAGIC, 4);
	WriteFileCell(hFile, iFileHeader.FH_binaryFormatVersion, 1);
	WriteFileCell(hFile, strlen(iFileHeader.FH_Time), 1);
	WriteFileString(hFile, iFileHeader.FH_Time, false);
	WriteFileCell(hFile, strlen(iFileHeader.FH_Playername), 1);
	WriteFileString(hFile, iFileHeader.FH_Playername, false);
	WriteFileCell(hFile, iFileHeader.FH_Checkpoints, 4);
	WriteFile(hFile, view_as<int>(iFileHeader.FH_initialPosition), 3, 4);
	WriteFile(hFile, view_as<int>(iFileHeader.FH_initialAngles), 2, 4);

	Handle hAdditionalTeleport;
	int iATIndex;
	GetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath, hAdditionalTeleport);

	int iTickCount = iFileHeader.FH_tickCount;
	WriteFileCell(hFile, iTickCount, 4);

	FrameInfo iFrame;
	for (int i = 0; i < iTickCount; i++)
	{
		GetArrayArray(iFileHeader.FH_frames, i, iFrame, sizeof(FrameInfo));
		WriteFile(hFile, view_as<int>(iFrame), sizeof(FrameInfo), 4);

		// Handle the optional Teleport call
		if (hAdditionalTeleport != null && iFrame.additionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY))
		{
			AdditionalTeleport iAT;
			GetArrayArray(hAdditionalTeleport, iATIndex, iAT, sizeof(AdditionalTeleport));
			if (iFrame.additionalFields & ADDITIONAL_FIELD_TELEPORTED_ORIGIN)
				WriteFile(hFile, view_as<int>(iAT.atOrigin), 3, 4);
			if (iFrame.additionalFields & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
				WriteFile(hFile, view_as<int>(iAT.atAngles), 3, 4);
			if (iFrame.additionalFields & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
				WriteFile(hFile, view_as<int>(iAT.atVelocity), 3, 4);
			iATIndex++;
		}
	}

	CloseHandle(hFile);
	LoadReplays();
}

public void LoadRecordFromFile(const char[] path, FileHeader headerInfo)
{
	Handle hFile = OpenFile(path, "rb");
	if (hFile == null)
		return;
	int iMagic;
	ReadFileCell(hFile, iMagic, 4);
	if (iMagic != BM_MAGIC)
	{
		CloseHandle(hFile);
		return;
	}
	int iBinaryFormatVersion;
	ReadFileCell(hFile, iBinaryFormatVersion, 1);
	headerInfo.FH_binaryFormatVersion = iBinaryFormatVersion;

	if (iBinaryFormatVersion > BINARY_FORMAT_VERSION)
	{
		CloseHandle(hFile);
		return;
	}

	int iNameLength;
	ReadFileCell(hFile, iNameLength, 1);
	char szTime[MAX_NAME_LENGTH];
	ReadFileString(hFile, szTime, iNameLength + 1, iNameLength);
	szTime[iNameLength] = '\0';

	int iNameLength2;
	ReadFileCell(hFile, iNameLength2, 1);
	char szName[MAX_NAME_LENGTH];
	ReadFileString(hFile, szName, iNameLength2 + 1, iNameLength2);
	szName[iNameLength2] = '\0';

	int iCp;
	ReadFileCell(hFile, iCp, 4);

	ReadFile(hFile, view_as<int>(headerInfo.FH_initialPosition), 3, 4);
	ReadFile(hFile, view_as<int>(headerInfo.FH_initialAngles), 2, 4);

	int iTickCount;
	ReadFileCell(hFile, iTickCount, 4);

	strcopy(headerInfo.FH_Time, 32, szTime);
	strcopy(headerInfo.FH_Playername, 32, szName);
	headerInfo.FH_Checkpoints = iCp;
	headerInfo.FH_tickCount = iTickCount;
	headerInfo.FH_frames = null;

	Handle hRecordFrames = CreateArray(sizeof(FrameInfo));
	Handle hAdditionalTeleport = CreateArray(AT_SIZE);

	FrameInfo iFrame;
	for (int i = 0; i < iTickCount; i++)
	{
		ReadFile(hFile, view_as<int>(iFrame), sizeof(FrameInfo), 4);
		PushArrayArray(hRecordFrames, iFrame, sizeof(FrameInfo));

		if (iFrame.additionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY))
		{
			AdditionalTeleport iAT;
			if (iFrame.additionalFields & ADDITIONAL_FIELD_TELEPORTED_ORIGIN)
				ReadFile(hFile, view_as<int>(iAT.atOrigin), 3, 4);
			if (iFrame.additionalFields & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
				ReadFile(hFile, view_as<int>(iAT.atAngles), 3, 4);
			if (iFrame.additionalFields & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
				ReadFile(hFile, view_as<int>(iAT.atVelocity), 3, 4);
			iAT.atFlags = iFrame.additionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY);
			PushArrayArray(hAdditionalTeleport, iAT, sizeof(AdditionalTeleport));
		}
	}

	headerInfo.FH_frames = hRecordFrames;

	if (GetArraySize(hAdditionalTeleport) > 0)
		SetTrieValue(g_hLoadedRecordsAdditionalTeleport, path, hAdditionalTeleport);

	CloseHandle(hFile);

	return;
}

public Action RefreshBot(Handle timer)
{
	setBotQuota();
	LoadRecordReplay();
	return Plugin_Handled;
}

public void LoadRecordReplay()
{
	g_RecordBot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsFakeClient(i) || i == g_InfoBot)
			continue;

		if (!IsPlayerAlive(i))
		{
			CS_RespawnPlayer(i);
			if (GetConVarBool(g_hForceCT))
				TeamChangeActual(i, 2);
		}

		g_RecordBot = i;
		g_fCurrentRunTime[g_RecordBot] = 0.0;
		g_bIsPlayingReplay = false;
		g_CurrentReplay = -1;
		break;
	}

	if (IsValidClient(g_RecordBot))
	{
		// Set trail
		if (GetConVarBool(g_hRecordBotTrail) && g_hBotTrail[0] == null)
			g_hBotTrail[0] = CreateTimer(5.0 , ReplayTrailRefresh, g_RecordBot, TIMER_REPEAT);

		char clantag[100];
		CS_GetClientClanTag(g_RecordBot, clantag, sizeof(clantag));
		if (StrContains(clantag, "REPLAY") == -1)
			g_bNewRecordBot = true;

		g_iClientInZone[g_RecordBot][2] = 0;

		CS_SetClientClanTag(g_RecordBot, "REPLAY");
		SetClientName(g_RecordBot, "Type !replay to watch");

		SetEntityRenderColor(g_RecordBot, g_ReplayBotColor[0], g_ReplayBotColor[1], g_ReplayBotColor[2], 50);
		if (GetConVarBool(g_hPlayerSkinChange))
		{
			char szBuffer[256];
			GetConVarString(g_hReplayBotPlayerModel, szBuffer, 256);
			SetEntityModel(g_RecordBot, szBuffer);

			GetConVarString(g_hReplayBotArmModel, szBuffer, 256);
			SetEntPropString(g_RecordBot, Prop_Send, "m_szArmsModel", szBuffer);
		}
	}
	else
	{
		CreateTimer(1.0, RefreshBot, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action RefreshBonusBot(Handle timer)
{
	setBotQuota();
	LoadBonusReplay();
	return Plugin_Handled;
}

public void LoadBonusReplay()
{
	/*g_BonusBot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsFakeClient(i) || i == g_InfoBot || i == g_RecordBot)
			continue;

		if (!IsPlayerAlive(i))
		{
			CS_RespawnPlayer(i);

			if (GetConVarBool(g_hForceCT))
				TeamChangeActual(i, 2);
		}

		g_BonusBot = i;
		g_fCurrentRunTime[g_BonusBot] = 0.0;
		break;
	}

	if (IsValidClient(g_BonusBot))
	{
		if (GetConVarBool(g_hBonusBotTrail) && g_hBotTrail[1] == null)
		{
			g_hBotTrail[1] = CreateTimer(5.0 , ReplayTrailRefresh, g_BonusBot, TIMER_REPEAT);
		}

		char clantag[100];
		CS_GetClientClanTag(g_BonusBot, clantag, sizeof(clantag));
		if (StrContains(clantag, "REPLAY") == -1)
			g_bNewBonusBot = true;
		g_iClientInZone[g_BonusBot][2] = g_iBonusToReplay[0];
		PlayRecord(g_BonusBot, 1);
		SetEntityRenderColor(g_BonusBot, g_BonusBotColor[0], g_BonusBotColor[1], g_BonusBotColor[2], 50);
		if (GetConVarBool(g_hPlayerSkinChange))
		{
			char szBuffer[256];
			GetConVarString(g_hReplayBotPlayerModel, szBuffer, 256);
			SetEntityModel(g_BonusBot, szBuffer);

			GetConVarString(g_hReplayBotArmModel, szBuffer, 256);
			SetEntPropString(g_BonusBot, Prop_Send, "m_szArmsModel", szBuffer);
		}
	}
	else
	{
		// Make sure bot_quota is set correctly and try again
		CreateTimer(1.0, RefreshBonusBot, TIMER_FLAG_NO_MAPCHANGE);
	}
	*/
}

public void StopPlayerMimic(int client)
{
	if (!IsValidClient(client))
		return;

	g_BotMimicTick[client] = 0;
	g_CurrentAdditionalTeleportIndex[client] = 0;
	g_BotMimicRecordTickCount[client] = 0;
	g_bValidTeleportCall[client] = false;
	SDKUnhook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
	g_hBotMimicsRecord[client] = null;
}

public bool IsPlayerMimicing(int client)
{
	if (!IsValidClient(client))
		return false;
	return g_hBotMimicsRecord[client] != null;
}

void DeleteReplay(int client, int zonegroup, char[] map)
{
	char sPath[PLATFORM_MAX_PATH + 1];
	if (zonegroup == 0) // Record
		Format(sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, map);
	else
		if (zonegroup > 0) // Bonus
			Format(sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, map, g_CurrentReplay);
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", sPath);

	// Delete the file
	if (FileExists(sPath))
	{
		if (!DeleteFile(sPath))
		{
			PrintToConsole(client, "<ERROR> Failed to delete %s - Please try to delete it manually!", sPath);
			return;
		}

		if (zonegroup > 0)
		{
			g_bMapBonusReplay[zonegroup] = false;
			PrintToConsole(client, "Bonus Replay %s_bonus_%i.rec deleted.", map, zonegroup);
		}
		else
		{
			g_bMapReplay = false;
			PrintToConsole(client, "Record Replay %s.rec deleted.", map);
		}
		if (StrEqual(map, g_szMapName))
		{
			if (zonegroup == 0 && IsValidClient(g_RecordBot))
			{
				KickClient(g_RecordBot);
				setBotQuota();
			}
		}
	}
	else
		PrintToConsole(client, "Failed! %s not found.", sPath);
}

public void RecordReplay (int client, int &buttons, int &subtype, int &seed, int &impulse, int &weapon, float angles[3], float vel[3])
{
	if (g_hRecording[client] != null && !IsFakeClient(client))
	{
		if (g_bPause[client]) //  Dont record pause frames
			return;

		FrameInfo iFrame;
		iFrame.playerButtons = buttons;
		iFrame.playerImpulse = impulse;

		float vVel[3];
		Entity_GetAbsVelocity(client, vVel);
		iFrame.actualVelocity = vVel;
		iFrame.predictedVelocity = vel;

		Array_Copy(angles, iFrame.predictedAngles, 2);
		iFrame.newWeapon = CSWeapon_NONE;
		iFrame.playerSubtype = subtype;
		iFrame.playerSeed = seed;

		// Save the current position
		if (g_OriginSnapshotInterval[client] > ORIGIN_SNAPSHOT_INTERVAL  || g_createAdditionalTeleport[client])
		{
			AdditionalTeleport iAT;
			float fBuffer[3];
			GetClientAbsOrigin(client, fBuffer);
			Array_Copy(fBuffer, iAT.atOrigin, 3);

			/*GetClientEyeAngles(client, fBuffer);
			Array_Copy(fBuffer, iAT.atAngles, 3);

			Entity_GetAbsVelocity(client, fBuffer);
			Array_Copy(fBuffer, iAT.atVelocity, 3);*/

			iAT.atFlags = ADDITIONAL_FIELD_TELEPORTED_ORIGIN;
			PushArrayArray(g_hRecordingAdditionalTeleport[client], iAT, sizeof(AdditionalTeleport));
			g_OriginSnapshotInterval[client] = 0;
			g_createAdditionalTeleport[client] = false;
		}

		g_OriginSnapshotInterval[client]++;

		// Check for additional Teleports
		if (GetArraySize(g_hRecordingAdditionalTeleport[client]) > g_CurrentAdditionalTeleportIndex[client])
		{
			AdditionalTeleport iAT;
			GetArrayArray(g_hRecordingAdditionalTeleport[client], g_CurrentAdditionalTeleportIndex[client], iAT, sizeof(AdditionalTeleport));
			// Remember, we were teleported this frame!
			iFrame.additionalFields |= iAT.atFlags;
			g_CurrentAdditionalTeleportIndex[client]++;
		}

		int iNewWeapon = -1;
		// Did he change his weapon?
		if (weapon)
			iNewWeapon = weapon;
		else // Picked up a new one?
		{
			int iWeapon = Client_GetActiveWeapon(client);
			if (iWeapon != -1 && (g_RecordedTicks[client] == 0 || g_RecordPreviousWeapon[client] != iWeapon))
				iNewWeapon = iWeapon;
		}

		if (iNewWeapon != -1)
		{
			if (IsValidEntity(iNewWeapon) && IsValidEdict(iNewWeapon))
			{
				g_RecordPreviousWeapon[client] = iNewWeapon;
				char sClassName[64];
				GetEdictClassname(iNewWeapon, sClassName, sizeof(sClassName));
				ReplaceString(sClassName, sizeof(sClassName), "weapon_", "", false);
				char sWeaponAlias[64];
				CS_GetTranslatedWeaponAlias(sClassName, sWeaponAlias, sizeof(sWeaponAlias));
				CSWeaponID weaponId = CS_AliasToWeaponID(sWeaponAlias);
				iFrame.newWeapon = weaponId;
			}
		}

		PushArrayArray(g_hRecording[client], iFrame, sizeof(FrameInfo));
		g_RecordedTicks[client]++;
	}
}

public void PlayReplay(int client, int &buttons, int &subtype, int &seed, int &impulse, int &weapon, float angles[3], float vel[3])
{
	if (g_hBotMimicsRecord[client] != null)
	{
		if (!IsPlayerAlive(client) || GetClientTeam(client) < CS_TEAM_T)
			return;

		if (g_BotMimicTick[client] >= g_BotMimicRecordTickCount[client] || g_bReplayAtEnd[client])
		{
			if (!g_bReplayAtEnd[client])
			{
				g_fReplayRestarted[client] = GetEngineTime();
				SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.0);
				g_bReplayAtEnd[client] = true;
			}

			if ((GetEngineTime() - g_fReplayRestarted[client]) < (BEAMLIFE))
				return;

			SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
			g_bReplayAtEnd[client] = false;
			g_BotMimicTick[client] = 0;
			g_CurrentAdditionalTeleportIndex[client] = 0;

			g_fLastReplayRequested[g_ReplayRequester] = GetGameTime();
			g_bIsPlayingReplay = false;
			g_ReplayCurrentStage = 0;

			CS_SetClientClanTag(g_RecordBot, "REPLAY");
			SetClientName(g_RecordBot, "Type !replay to watch");

			return;
		}
		if (CheckHideBotWeapon(client))
			StripAllWeapons(g_RecordBot);
		
		FrameInfo iFrame;
		GetArrayArray(g_hBotMimicsRecord[client],
						g_BotMimicTick[client],
						iFrame,
						sizeof(FrameInfo)
					);

		buttons = iFrame.playerButtons;
		impulse = iFrame.playerImpulse;
		Array_Copy(iFrame.predictedVelocity, vel, 3);
		Array_Copy(iFrame.predictedAngles, angles, 2);
		subtype = iFrame.playerSubtype;
		seed = iFrame.playerSeed;
		weapon = 0;

		float fActualVelocity[3];
		Array_Copy(iFrame.actualVelocity, fActualVelocity, 3);

		// We're supposed to teleport stuff?
		if (iFrame.additionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY))
		{
			AdditionalTeleport iAT;
			Handle hAdditionalTeleport;
			char sPath[PLATFORM_MAX_PATH];
			if (g_CurrentReplay == 0)
				Format(sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
			else if (g_CurrentReplay > 0)
				Format(sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, g_CurrentReplay);
			else if (g_CurrentReplay < 0 && g_ReplayCurrentStage > 0)
				Format(sPath, sizeof(sPath), "%s%s_stage_%i.rec", CK_REPLAY_PATH, g_szMapName, g_ReplayCurrentStage);

			BuildPath(Path_SM, sPath, sizeof(sPath), "%s", sPath);
			if (g_hLoadedRecordsAdditionalTeleport != null)
			{
				GetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath, hAdditionalTeleport);
				if (hAdditionalTeleport != null)
					GetArrayArray(hAdditionalTeleport, g_CurrentAdditionalTeleportIndex[client], iAT, sizeof(AdditionalTeleport));

				float fOrigin[3], fAngles[3], fVelocity[3];
				Array_Copy(iAT.atOrigin, fOrigin, 3);
				Array_Copy(iAT.atAngles, fAngles, 3);
				Array_Copy(iAT.atVelocity, fVelocity, 3);

				// The next call to Teleport is ok.
				g_bValidTeleportCall[client] = true;

				if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_ORIGIN)
				{
					if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
					{
						if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, fOrigin, fAngles, fVelocity);
						else
							TeleportEntity(client, fOrigin, fAngles, NULL_VECTOR);
					}
					else
					{
						if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, fOrigin, NULL_VECTOR, fVelocity);
						else
							TeleportEntity(client, fOrigin, NULL_VECTOR, NULL_VECTOR);
					}
				}
				else
				{
					if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
					{
						if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, NULL_VECTOR, fAngles, fVelocity);
						else
							TeleportEntity(client, NULL_VECTOR, fAngles, NULL_VECTOR);
					}
					else
					{
						if (iAT.atFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
					}
				}
				g_CurrentAdditionalTeleportIndex[client]++;
			}
		}

		// This is the first tick. Teleport him to the initial position
		if (g_BotMimicTick[client] == 0)
		{
			CL_OnStartTimerPress(client);
			g_bValidTeleportCall[client] = true;
			TeleportEntity(client, g_fInitialPosition[client], g_fInitialAngles[client], fActualVelocity);

		}
		else
		{
			g_bValidTeleportCall[client] = true;
			TeleportEntity(client, NULL_VECTOR, angles, fActualVelocity);
		}

		if (iFrame.newWeapon != CSWeapon_NONE)
		{
			char sAlias[64];
			CS_WeaponIDToAlias(iFrame.newWeapon, sAlias, sizeof(sAlias));

			Format(sAlias, sizeof(sAlias), "weapon_%s", sAlias);

			if (g_BotMimicTick[client] > 0 && Client_HasWeapon(client, sAlias))
			{
				weapon = Client_GetWeapon(client, sAlias);
				g_BotActiveWeapon[client] = weapon;
				InstantSwitch(client, weapon);
			}
			else
			{
				if ((client == g_RecordBot && g_bNewRecordBot))
				{
					bool hasweapon;
					if (client == g_RecordBot)
						g_bNewRecordBot = false;

					if (StrEqual(sAlias, "weapon_hkp2000") && !hasweapon)
					{
						if (Client_HasWeapon(client, "weapon_hkp2000"))
						{
							weapon = Client_GetWeapon(client, sAlias);
							g_BotActiveWeapon[client] = weapon;
							hasweapon = true;
							InstantSwitch(client, weapon);

						}
						Format(sAlias, sizeof(sAlias), "weapon_usp_silencer", sAlias);
					}

					if (!hasweapon)
					{
						weapon = GivePlayerItem(client, sAlias);
						if (weapon != INVALID_ENT_REFERENCE)
						{
							g_BotActiveWeapon[client] = weapon;
							// Grenades shouldn't be equipped.
							if (StrContains(sAlias, "grenade") == -1
								 && StrContains(sAlias, "flashbang") == -1
								 && StrContains(sAlias, "decoy") == -1
								 && StrContains(sAlias, "molotov") == -1)
							{
								EquipPlayerWeapon(client, weapon);
							}
							InstantSwitch(client, weapon);
						}
					}
				}
				else
				{
					weapon = Client_GetWeapon(client, sAlias);
					g_BotActiveWeapon[client] = weapon;
					InstantSwitch(client, weapon);
				}
			}
		}
		g_BotMimicTick[client]++;
	}
}



public void Stage_StartRecording(int client)
{
	GetClientAbsOrigin(client, g_fStageInitialPosition[client]);
	GetClientEyeAngles(client, g_fStageInitialAngles[client]);

	// Client is being recorded, save the ticks where the recording started
	if (g_hRecording[client] != null) {
		g_StageRecStartFrame[client] = g_RecordedTicks[client];
		g_StageRecStartAT[client] = g_CurrentAdditionalTeleportIndex[client];
		return;
	}

	StartRecording(client);
	g_StageRecStartFrame[client] = 0;
	g_StageRecStartAT[client] = 0;
}


public void Stage_SaveRecording(int client, int stage, char[] time)
{
	if (!IsValidClient(client) || g_hRecording[client] == null) {
		return;
	}
	

	char sPath2[256];

	// Check if the default record folder exists?
	BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s", CK_REPLAY_PATH);
	if (!DirExists(sPath2))
	{
		CreateDirectory(sPath2, 511);
	}

	BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, stage);
	

	if (FileExists(sPath2) && GetConVarBool(g_hBackupReplays))
	{
		char newPath[256];
		Format(newPath, 256, "%s.bak", sPath2);
		RenameFile(newPath, sPath2);
	}

	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);


	int startframe = g_StageRecStartFrame[client];
	int framesRecorded = GetArraySize(g_hRecording[client]) - startframe;

	FileHeader iHeader;
	iHeader.FH_binaryFormatVersion = BINARY_FORMAT_VERSION;
	strcopy(iHeader.FH_Time, 32, time);
	iHeader.FH_tickCount = framesRecorded;
	strcopy(iHeader.FH_Playername, 32, szName);
	iHeader.FH_Checkpoints = 0; // So that KZTimers replays work
	Array_Copy(g_fStageInitialPosition[client], iHeader.FH_initialPosition, 3);
	Array_Copy(g_fStageInitialAngles[client], iHeader.FH_initialAngles, 3);

	Handle frames = CreateArray(sizeof(FrameInfo));

	for (int i = startframe; i < GetArraySize(g_hRecording[client]); i++)
	{
		int iFrame[FRAME_INFO_SIZE];
		GetArrayArray(g_hRecording[client], i, iFrame, sizeof(FrameInfo));
		PushArrayArray(frames, iFrame, sizeof(FrameInfo));
	}

	iHeader.FH_frames = frames;

	if (GetArraySize(g_hRecordingAdditionalTeleport[client]) > 0)
	{
		Handle additionalteleports = CreateArray(sizeof(AdditionalTeleport));

		for (int i = g_StageRecStartAT[client]; i < GetArraySize(g_hRecordingAdditionalTeleport[client]); i++)
		{
			AdditionalTeleport iAT;
			GetArrayArray(g_hRecordingAdditionalTeleport[client], i, iAT, AT_SIZE);
			PushArrayArray(additionalteleports, iAT, AT_SIZE);
		}

		SetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath2, additionalteleports);
	}

	WriteRecordToDisk(sPath2, iHeader);
}