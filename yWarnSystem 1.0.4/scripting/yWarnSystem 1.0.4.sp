/**** ✖ Lista Zmian ✖ **** 

1.0.0 - Pierwsze Wydanie Pluginu.
1.0.1 - Dodano możliwośc ustawienia własnego tagu.
1.0.2 - Poprawa błędów.
1.0.3 - Poprawa błędów , zmiana struktury configu , optymalizacja kodu.
1.0.4 - Dodano możliwosc wyboru Ban/Gag.

✖ ****                  ****/

#include <sourcemod>
#include <sdkhooks>
#include <sourcebanspp>
#include <sourcecomms>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required
#pragma tabsize 0

#define KvPath "configs/yWarnSystem.cfg"

int g_iWarning[MAXPLAYERS + 1];
int g_nWarning[MAXPLAYERS + 1];
int powtorzenie[MAXPLAYERS + 1];

ArrayList Array_BannedWords;
char configFile[PLATFORM_MAX_PATH];
char MOD_TAG[64];

ConVar y_Mod_Tag;
ConVar g_TimePunishment;
ConVar g_PluginMode;

bool g_bInitialized[MAXPLAYERS + 1];

Database DB;

public Plugin myinfo = {
	name = "[ yWarnSystem ]", 
	author = "fabko & y0ung | Thanks for fabko for the codebase", 
	description = "[ yWarnSystem 1.0.4 ]", 
	version = "1.0.4", 
	url = "FeelTheGame.eu"
};

public void OnPluginStart() {
	g_PluginMode = CreateConVar("y_Plugin_Mode", "1", "Wybierz który tryb pluginu ma funkcjonować 1 = Ban | 0 = Gag");
	g_TimePunishment = CreateConVar("y_Punishment_Time", "1", "Czas trwania Bana/Gaga. (Domyślnie 1 minuta)", _, true, 0.0);
	y_Mod_Tag = CreateConVar("y_Chat_Tag", "y0ung", "Twój Tag - WarnSystem");
	y_Mod_Tag.AddChangeHook(MOD_TAGNameChanged);
	y_Mod_Tag.GetString(MOD_TAG, sizeof(MOD_TAG));
	Array_BannedWords = new ArrayList(128);
	BuildPath(Path_SM, configFile, sizeof(configFile), KvPath);
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	AutoExecConfig(true, "yWarnSystem");
	DB_Connect();
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			g_bInitialized[i] = false;
			SQL_LoadData(i);
		}
	}
}

public void MOD_TAGNameChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	Format(MOD_TAG, sizeof(MOD_TAG), newValue);
}

public void OnMapStart() {
	Array_BannedWords.Clear();
	LoadWords();
}

public void OnMapEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i))SQL_SaveData(i);
	}
}

public void OnClientPostAdminCheck(int client) {
	g_bInitialized[client] = false;
	SQL_LoadData(client);
}
public void OnClientDisconnect(int client) {
	SQL_SaveData(client);
	g_iWarning[client] = 0;
	g_nWarning[client] = 0;
	powtorzenie[client] = 0;
	g_bInitialized[client] = false;
}

void DB_Connect() {
	if (SQL_CheckConfig("y_warn_system"))
	{
		char error[512];
		DB = SQL_Connect("y_warn_system", true, error, sizeof(error));
		if (DB == null) {
			SetFailState("Could not connect to y_warn_system! Error: %s", error);
			return;
		}
		else
		{
			char query[512];
			DB.SetCharset("utf8");
			Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `y_users` (`auth_data` VARCHAR(64) NOT NULL, `name` VARCHAR(64) NOT NULL, `iWarnings` INT NOT NULL, `nWarnings` INT NOT NULL, `powtorzenie` INT NOT NULL, PRIMARY KEY(`auth_data`)) ENGINE=InnoDB DEFAULT CHARSET= `utf8` COLLATE=`utf8_general_ci`;");
			DB.Query(CreateTableHandler, query, _, DBPrio_Normal);
		}
	}
	else SetFailState("Nie mozna odnalezc konfiguracji 'y_warn_system' w databases.cfg. ");
}

public void CreateTableHandler(Database db, DBResultSet results, const char[] error, any data) {
	if (db == null) {
		LogMessage("Could not create tables! Error: %s", error);
	}
	delete results;
}

void SQL_LoadData(int client) {
	char steamid[64];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	char query[512];
	Format(query, sizeof(query), "SELECT iWarnings, nWarnings, powtorzenie FROM y_users WHERE auth_data = '%s'", steamid);
	DB.Query(LoadDataHandler, query, GetClientUserId(client), DBPrio_High);
}

public void LoadDataHandler(Database db, DBResultSet results, const char[] error, int userid) {
	if (db == null) {
		LogMessage("Could not load user data! Error: %s", error);
		return;
	}
	int client = GetClientOfUserId(userid);
	if (!client)return;
	if (IsClientInGame(client) && !IsFakeClient(client) && !g_bInitialized[client])
	{
		if (results.RowCount == 0) {
			char query[256], name[256], steamid[64];
			GetClientName(client, name, sizeof(name));
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			char sanitized_name[128];
			DB.Escape(name, sanitized_name, sizeof(name));
			
			Format(query, sizeof(query), "INSERT INTO `y_users` (auth_data, name, iWarnings, nWarnings, powtorzenie) VALUES ('%s', '%s', 0, 0, 0)", steamid, sanitized_name);
			DB.Query(InsertNewPlayer, query, GetClientUserId(client), DBPrio_High);
		}
		else {
			while (results.FetchRow()) {
				g_iWarning[client] = results.FetchInt(0);
				g_nWarning[client] = results.FetchInt(1);
				powtorzenie[client] = results.FetchInt(2);
			}
		}
		g_bInitialized[client] = true;
	}
	delete results;
}

public void InsertNewPlayer(Database db, DBResultSet results, const char[] error, any data) {
	if (db == null) {
		LogMessage("Could not insert player! Error: %s", error);
	}
	delete results;
}

void SQL_SaveData(int client)
{
	if (CheckStatus(client))
	{
		char query[512], name[256], steamid[64];
		GetClientName(client, name, sizeof(name));
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		char sanitized_name[128];
		DB.Escape(name, sanitized_name, sizeof(name));
		Format(query, sizeof(query), "UPDATE `y_users` SET `name`='%s', `iWarnings`= %d, `nWarnings`= %d, `powtorzenie`= %d WHERE auth_data = '%s'", sanitized_name, g_iWarning[client], g_nWarning[client], powtorzenie[client], steamid);
		DB.Query(UpdatePlayerData, query, _, DBPrio_High);
	}
}

public void UpdatePlayerData(Database db, DBResultSet results, const char[] error, any data) {
	if (db == null) {
		LogMessage("Could not update player data! Error: %s", error);
	}
	delete results;
}

public Action Command_Say(int client, const char[] command, int argc) {
	char sName[MAX_NAME_LENGTH];
	char sText[128];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	GetClientName(client, sName, sizeof(sName));
	for (int i = 0; i < Array_BannedWords.Length; i++)
	{
		char buffer[128];
		Array_BannedWords.GetString(i, buffer, sizeof(buffer));
		if (StrContains(sText, buffer, false) != -1)
		{
			g_iWarning[client]++;
			switch (g_iWarning[client])
			{
				case 1:CPrintToChat(client, "{yellow}★ {darkblue}[%s {darkred}» {default}WarnSystem] {green}Otrzymujesz pierwsze ostrzeżenie za wulgarne słownictwo!", MOD_TAG);
				case 2:CPrintToChat(client, "{yellow}★ {darkblue}[%s {darkred}» {default}WarnSystem] {green}Dostałeś drugie ostrzeżenie!", MOD_TAG);
				case 3:CPrintToChat(client, "{yellow}★ {darkblue}[%s {darkred}» {default}WarnSystem] {green}Dostałeś trzecie ostrzeżenie! Za 4 zostaniesz zbanowany!", MOD_TAG);
			}
		}
	}
	if (g_iWarning[client] > 3) {
		g_iWarning[client] = 0;
		g_nWarning[client] = 0;
		powtorzenie[client] = 0;
		if (g_PluginMode.BoolValue)
			SBPP_BanPlayer(0, client, g_TimePunishment.IntValue, "Zostałeś zbanowany za użycie wulgarnych słów");
		else
		{
			SourceComms_SetClientGag(client, true, g_TimePunishment.IntValue, true, "Zostałeś wyciszony za użycie wulgarnych słów");
			CPrintToChat(client, "{yellow}★ {darkblue}[%s {darkred}» {default}WarnSystem] {darkred}Zostałeś wyciszony za używanie wulgarnych słów, zachowuj się", MOD_TAG);
			CPrintToChatAll("{yellow}★ {darkblue}[%s {darkred}» {default}WarnSystem] {yellow}Gracz {green}%s {yellow}został {darkred}WYCISZONY {yellow}za używanie wulgarnych słów", MOD_TAG, sName);
		}
	}
}

void LoadWords() {
	char inFile[PLATFORM_MAX_PATH], line[512];
	BuildPath(Path_SM, inFile, sizeof(inFile), "configs/yWarnSystem.cfg");
	if (!FileExists(inFile))PrintToServer("[WARNING] Nie znaleziono pliku: %s [WARNING]", inFile);
	Handle file = OpenFile(inFile, "rt");
	if (file != INVALID_HANDLE)
	{
		while (!IsEndOfFile(file))
		{
			if (!ReadFileLine(file, line, sizeof(line))) {
				break;
			}
			TrimString(line);
			if (strlen(line) > 0)
			{
				if (StrContains(line, "//") != -1)
					continue;
				
				Array_BannedWords.PushString(line);
			}
		}
		CloseHandle(file);
	}
}

bool CheckStatus(int client) {
	if (client && IsClientInGame(client) && !IsFakeClient(client) && g_bInitialized[client]) {
		return true;
	}
	else g_bInitialized[client] = false;
	return false;
}

bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || !IsClientConnected(client) || IsFakeClient(client) || IsClientSourceTV(client))
		return false;
	
	return true;
} 