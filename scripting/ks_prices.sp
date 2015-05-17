#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <steamtools>

#define KILLSTREAKS_TF_URL "http://www.killstreaks.tf/api/price_search/"

new Handle:cvarTag;

new Handle:sv_tags;

public Plugin:myinfo = 
{
	name = "Killstreaks.tf Price Fetcher",
	author = "Sisco++",
	description = "Fetches item prices from the KS.tf website based on a user supplied search string.",
	version = "0.1",
	url = "http://www.killstreaks.tf/"
};



public OnPluginStart()
{
	RegConsoleCmd("sm_ksprice", Command_KSTF_Price, "Usage: sm_ksprice <item>");
	RegConsoleCmd("sm_ksp", Command_KSTF_Price, "Usage: sm_ksp <item>");
	
	
	cvarTag = CreateConVar("killstreaks_tf_add_tag", "1", "If 1, adds the killstreaks.tf tag to your server's sv_tags.", _, true, 0.0, true, 1.0);
	
	sv_tags = FindConVar("sv_tags");
}


public OnConfigsExecuted() {
	CreateTimer(2.0, Timer_AddTag); // Let everything load first
}

public Action:Timer_AddTag(Handle:timer) {
	if(!GetConVarBool(cvarTag)) {
		return;
	}
	decl String:value[512];
	GetConVarString(sv_tags, value, sizeof(value));
	TrimString(value);
	if(strlen(value) == 0) {
		SetConVarString(sv_tags, "killstreaks.tf");
		return;
	}
	decl String:tags[64][64];
	new total = ExplodeString(value, ",", tags, sizeof(tags), sizeof(tags[]));
	for(new i = 0; i < total; i++) {
		if(StrEqual(tags[i], "killstreaks.tf")) {
			return; // Tag found, nothing to do here
		}
	}
	StrCat(value, sizeof(value), ",killstreaks.tf");
	SetConVarString(sv_tags, value);
}


 
public Action:Command_KSTF_Price(client, args)
{
	if (args == 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_ksprice <item>");
		return Plugin_Handled;
	}
	
	decl String:query[256], String:cID[8];
	GetCmdArgString(query, sizeof(query));
	StripQuotes(query);
	
	IntToString(GetClientUserId(client), cID, sizeof(cID));
	
	new HTTPRequestHandle:request = Steam_CreateHTTPRequest(HTTPMethod_GET, KILLSTREAKS_TF_URL);
	Steam_SetHTTPRequestGetOrPostParameter(request, "search", query);
	Steam_SetHTTPRequestGetOrPostParameter(request, "minimal", "1");
	Steam_SetHTTPRequestGetOrPostParameter(request, "format", "vdf");
	Steam_SendHTTPRequest(request, OnKillstreaksTFResponse, GetClientUserId(client));
	
	
	return Plugin_Handled;
}


public OnKillstreaksTFResponse(HTTPRequestHandle:request, bool:successful, HTTPStatusCode:status, any:userid) {

	new client = GetClientOfUserId(userid);
	if(client == 0) {
		LogError("Client with User ID %d left.", userid);
		Steam_ReleaseHTTPRequest(request);
		return;
	}
	
	if(status != HTTPStatusCode_OK || !successful) {
		if(status == HTTPStatusCode_BadRequest) {
			PrintToChat(client, "KillStreaks.TF API failed: You have not set an API key");
			Steam_ReleaseHTTPRequest(request);
			return;
			
		} else if(status == HTTPStatusCode_Forbidden) {
			PrintToChat(client, "KillStreaks.TF API failed: Your API key is invalid");
			Steam_ReleaseHTTPRequest(request);
			return;
			
		} else if(status == HTTPStatusCode_PreconditionFailed) {
			decl String:retry[16];
			Steam_GetHTTPResponseHeaderValue(request, "Retry-After", retry, sizeof(retry));
			PrintToChat(client, "KillStreaks.TF API failed: We are being rate-limited by KillStreaks.TF, next request allowed in %s seconds", retry);
			
		} else if(status >= HTTPStatusCode_InternalServerError) {
			PrintToChat(client, "KillStreaks.TF API failed: An internal server error occurred");
			
		} else if(status == HTTPStatusCode_OK && !successful) {
			PrintToChat(client, "KillStreaks.TF API failed: KillStreaks.TF returned an OK response but no data");
			
		} else if(status != HTTPStatusCode_Invalid) {
			PrintToChat(client, "KillStreaks.TF API failed: Unknown error (status code %d)", _:status);
			
		} else {
			PrintToChat(client, "KillStreaks.TF API failed: Unable to connect to server or server returned no data");
			
		}
		Steam_ReleaseHTTPRequest(request);
		return;
	}
	
	new bSize = Steam_GetHTTPResponseBodySize(request);	
	decl String:data[bSize];
	
	Steam_GetHTTPResponseBodyData(request, data, bSize);
	Steam_ReleaseHTTPRequest(request);
	
	//PrintToServer("%s", data);	
	//PrintToServer("KillStreaks.TF query success: (ClientID: %N) %s", client, data);
	
	new Handle:KvData = CreateKeyValues("Response");
	if( !StringToKeyValues(KvData, data) )
	{
		CloseHandle(KvData);
		return;
	}	
	new success = KvGetNum(KvData, "success", -1);
	
	if(success == 1)
	{
		KvGotoFirstSubKey(KvData);//now in 'items'
		KvGotoFirstSubKey(KvData);//now in the first section/key within 'items'
		do
		{
			decl String:str[512];
			decl String:title[128];
			decl String:price[128];
			
			KvGetString(KvData, "title", title, sizeof(title), "<error>");
			KvGetString(KvData, "base", price, sizeof(price), "<error>");
			Format(str, sizeof(str), "\x03%s\x01 (\x04%s\x01)", title, price);
		
			PrintToChat(client, "\x076060EE[\x07EE6060KS\x076060EE] \x01%s", str);
		} while (KvGotoNextKey(KvData));
		
	}
	else
	{
		decl String:err[512];
		KvGetString(KvData, "error", err, sizeof(err), "<ERROR>");
		
		PrintToChat(client, "\x076060EE[\x07EE6060KS\x076060EE] \x01%s", err);
	}
	
	CloseHandle(KvData);
}

//GetClientOfUserId