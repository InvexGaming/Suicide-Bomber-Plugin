#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include "colors_csgo.inc"
#include "emitsoundany.inc"

#define PLUGIN_VERSION "1.01"

/*
* Plugin Information - Please do not change this
*/
public Plugin:myinfo =
{
  name        = "Suicide Bomber",
  author      = "Invex | Byte",
  description = "Disables bomb sites and allows bomb carrier to suicide to kill all players around them.",
  version     = PLUGIN_VERSION,
  url         = "http://www.invexgaming.com.au"
};

//Definitions
#define BOMB_SLOT 4
#define ASCII_LOWER_START 97

new String:PREFIX[] = "[{olive}SuicideBomber{default}] ";
new Handle:bombCarriers = INVALID_HANDLE;
new Handle:originalCarriers = INVALID_HANDLE;
new bombEntIndex[MAXPLAYERS+1] = {-1, ...}; //All bomb entities
new numKilledPlayers[MAXPLAYERS+1] = {0, ...}; //Number of players each sucide bomber kills
new diedByBomb[MAXPLAYERS+1] = {-1, ...}; //if non -1, contains client who killed said player
new bool:isBombEquipedByPlayer[MAXPLAYERS+1] = {false, ...}; //True if player currently has bomb equiped
new bool:showUseErrorMessage[MAXPLAYERS+1] = {true, ...};
new bool:isSpawnProtection = false;
new bool:isEnabled;
new String:EXPLOSION_SOUND_PATH[256] = "";

//Handles
new Handle:g_suicide_bomber_enabled = INVALID_HANDLE;
new Handle:g_disable_bomb_sites = INVALID_HANDLE;
new Handle:g_max_c4_distributed = INVALID_HANDLE;
new Handle:g_bots_can_have_bomb = INVALID_HANDLE;
new Handle:g_VIP_enabled = INVALID_HANDLE;
new Handle:g_VIP_flag = INVALID_HANDLE;
new Handle:g_VIP_entries = INVALID_HANDLE;
new Handle:g_sp_time = INVALID_HANDLE;
new Handle:g_highlightPlayer_RED = INVALID_HANDLE;
new Handle:g_highlightPlayer_GREEN = INVALID_HANDLE;
new Handle:g_highlightPlayer_BLUE = INVALID_HANDLE;
new Handle:g_explosion_sound = INVALID_HANDLE;

new g_ExplosionSprite;
new RenderOffs;

enum FX
{
  FxNone = 0,
  FxPulseFast,
  FxPulseSlowWide,
  FxPulseFastWide,
  FxFadeSlow,
  FxFadeFast,
  FxSolidSlow,
  FxSolidFast,
  FxStrobeSlow,
  FxStrobeFast,
  FxStrobeFaster,
  FxFlickerSlow,
  FxFlickerFast,
  FxNoDissipation,
  FxDistort,               // Distort/scale/translate flicker
  FxHologram,              // kRenderFxDistort + distance fade
  FxExplode,               // Scale up really big!
  FxGlowShell,             // Glowing Shell
  FxClampMinScale,         // Keep this sprite from getting very small (SPRITES only!)
  FxEnvRain,               // for environmental rendermode, make rain
  FxEnvSnow,               //  "        "            "    , make snow
  FxSpotlight,     
  FxRagdoll,
  FxPulseFastWider,
};

enum Render
{
  Normal = 0,     // src
  TransColor,     // c*a+dest*(1-a)
  TransTexture,    // src*a+dest*(1-a)
  Glow,        // src*a+dest -- No Z buffer checks -- Fixed size in screen space
  TransAlpha,      // src*srca+dest*(1-srca)
  TransAdd,      // src*a+dest
  Environmental,    // not drawn, used for environmental effects
  TransAddFrameBlend,  // use a fractional frame value to blend between animation frames
  TransAlphaAdd,    // src + dest*(1-a)
  WorldGlow,      // Same as kRenderGlow but not fixed size in screen space
  None,        // Don't render.
};


/*
* Plugin Start
*/
public OnPluginStart()
{
  //Load translation
  LoadTranslations("suicidebomber.phrases");
  
  //ConVar List
  CreateConVar("sm_suicidebomber_version", PLUGIN_VERSION, "Version of 'Suicide Bomber' plugin", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
  g_suicide_bomber_enabled = CreateConVar("sm_suicidebomber_enabled", "1", "Enable Suicide Bomber Plugin (0 off, 1 on, def. 1)");
  g_disable_bomb_sites = CreateConVar("sm_suicidebomber_killbombsite", "1", "Disable bomb sites (0 off, 1 on, def. 1)");
  g_max_c4_distributed = CreateConVar("sm_suicidebomber_maxc4num", "1", "Maximum number of C4 explosives to distribute (def. 1)");
  g_bots_can_have_bomb = CreateConVar("sm_suicidebomber_botscanhavebomb", "0", "Are bots allowed to be given the bomb (def. 0)");
  g_VIP_enabled = CreateConVar("sm_suicidebomber_vipenabled", "0", "Enable VIP features. (def. 0)");
  g_VIP_flag = CreateConVar("sm_suicidebomber_vipflag", "q", "VIP flag to give users a higher chance of receiving the bomb. Single letter, lowercase. (def. 'q')")
  g_VIP_entries = CreateConVar("sm_suicidebomber_vippickchance", "3", "How many entries (total) do VIP players get when picking suicide bombers (min. 1, def. 3)");
  g_sp_time = CreateConVar("sm_suicidebomber_sptime", "0.0", "Set this to a non-zero value if you use a spawn protection plugin that colours player models. Leave as 0.0 to autodetect some spawn protection plugins. (min. 0.0, def. 0.0)");
  g_highlightPlayer_RED = CreateConVar("sm_suicidebomber_highlight_RED", "255", "Amount of red in suicide bomber player colour. (min. 0, max. 255, def. 255)");
  g_highlightPlayer_GREEN = CreateConVar("sm_suicidebomber_highlight_GREEN", "0", "Amount of green in suicide bomber player colour. (min. 0, max. 255, def. 0)");
  g_highlightPlayer_BLUE = CreateConVar("sm_suicidebomber_highlight_BLUE", "0", "Amount of blue in suicide bomber player colour. (min. 0, max. 255, def. 0)");
  g_explosion_sound = CreateConVar("sm_suicidebomber_explosion_sound", "sound/invex_gaming/misc/wtfboom_scream.mp3", "Explosion sound to play when a suicider bomber suicides. (def. \"sound/invex_gaming/misc/wtfboom_scream.mp3\")")
  
  //Attempt to automatically set g_sp_time if running Spawn Protection [Added CS:GO Support] by Fredd
  new Handle:freddSP = FindConVar("sp_time");
  if (freddSP != INVALID_HANDLE && GetConVarFloat(g_sp_time) == 0.0)
    SetConVarFloat(g_sp_time, GetConVarFloat(freddSP));
  
  //Event hooks
  HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
  HookEvent("round_start", Event_RoundStart);
  HookEvent("bomb_dropped", Event_BombDrop);
  HookEvent("bomb_pickup", Event_BombPickUp);
  HookEvent("bomb_pickup", Event_BombPickUpPre, EventHookMode_Pre);
  
  //Set random number seed
  SetRandomSeed(GetTime());
  
  //Enable status hook
  HookConVarChange(g_suicide_bomber_enabled, ConVarChange_enabled);
  
  //Find render offs
  RenderOffs = FindSendPropOffs("CBasePlayer", "m_clrRender");
  
  //Init arrays
  bombCarriers = CreateArray();
  originalCarriers = CreateArray();
  
  //Set Variable Values
  isEnabled = true;
  
  AutoExecConfig(true, "suicide_bomber");
}

/*
* On Map Start
*/
public OnMapStart()
{
  if (!isEnabled) 
    return;
  
  //Precache sounds
  new String:explosionSoundStrPath[256];
  GetConVarString(g_explosion_sound, explosionSoundStrPath, sizeof(explosionSoundStrPath));
  AddFileToDownloadsTable(explosionSoundStrPath);
  ReplaceString(explosionSoundStrPath, sizeof(explosionSoundStrPath), "sound/", ""); //Remove sound folder prefix
  PrecacheSoundAny(explosionSoundStrPath);
  strcopy(EXPLOSION_SOUND_PATH, sizeof(EXPLOSION_SOUND_PATH), explosionSoundStrPath);
  
  //Precache materials
  g_ExplosionSprite = PrecacheModel("sprites/sprite_flames.vmt");
  
  if (GetConVarBool(g_disable_bomb_sites)) {
    //Remove all real bomb sites
    new iEnt = -1;
    while((iEnt = FindEntityByClassname(iEnt, "func_bomb_target")) != -1) { //Find bombsites
      AcceptEntityInput(iEnt,"kill"); //Destroy the entity
    }
    
    //Create a fake bomb site
    //This allows bomb to show up on radar
    DispatchSpawn(CreateEntityByName("func_bomb_target"));
  }
  
  //Disable the bomb distribution cvar
  //We will handle distribution of C4s
  SetConVarInt(FindConVar("mp_give_player_c4"), 0);

}

/*
* If enable convar is changed, use this to turn the plugin off or on
*/
public ConVarChange_enabled(Handle:convar, const String:oldValue[], const String:newValue[])
{
  isEnabled = bool:StringToInt(newValue) ;
}

/*
* Round Start
*/
public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  //Reset bomb carrier arrays
  ClearArray(bombCarriers);
  ClearArray(originalCarriers);
  
  //Set spawn protection to be on
  isSpawnProtection = true;
  CreateTimer(15.0, TurnOffSpawnProtectoon);
  
  //Get terrorist list
  new Handle:terroristList = CreateArray();
  new terroristCount = 0;
  new bool:botCanHaveBomb = GetConVarBool(g_bots_can_have_bomb);
  
  for (new i = 1; i <= MaxClients; ++i) { 
    if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
      
      //Check if bot and if bot is allowed to have bomb
      if (IsFakeClient(i) && !botCanHaveBomb)
        continue;
      
      new numEntries = 1;
      
      //Check if user is a VIP player if VIP mode is on
      if (GetConVarBool(g_VIP_enabled)) {
        new String:flag[2];
        GetConVarString(g_VIP_flag, flag, sizeof(flag)); //get flag as string
        new flagNum = flag[0]; //get ascii int
        
        new ADMFLAG_PROVIDED = (1 << (flagNum - ASCII_LOWER_START));
        if (CheckCommandAccess(i, "", ADMFLAG_PROVIDED))
          numEntries = GetConVarInt(g_VIP_entries); //VIP players are more likely to get bomb 
      }

      //Add entries for this player
      for (new j = 0; j < numEntries; ++j) {
        PushArrayCell(terroristList, i);
        ++terroristCount; 
      }
    }
  }
  
  if (terroristCount == 0) //no terrorists
    return Plugin_Continue;
  
  //Distribute C4 Explosives
  new maxC4num = GetConVarInt(g_max_c4_distributed);
  
  if (maxC4num > terroristCount)
    maxC4num = terroristCount;
  
  for(new i = 0; i < maxC4num; ++i) {
    //Generate a random number
    new randIndex = GetRandomInt(0, terroristCount - 1);
    --terroristCount; //decrement terroristCount
    
    new chosenT = GetArrayCell(terroristList, randIndex);
    RemoveFromArray(terroristList, randIndex); //remove index so chosenT isn't picked again
    
    //Make sure we haven't already picked this T
    new isOriginalCarrier = FindValueInArray(originalCarriers, chosenT);
    if (isOriginalCarrier != -1)  //If already picked, continue
      continue;
    
    //Set this T as a original carrier
    PushArrayCell(originalCarriers, chosenT);
    
    //Give this chosen T a C4
    GivePlayerItem(chosenT, "weapon_c4");
    
    //Readd colour after 15 seconds, needed due to spawn protection
    CreateTimer(15.2, ReAddRedGlow, chosenT, chosenT);
    
    //Let them know!
    CPrintToChat(chosenT, "%s%t", PREFIX, "You Are Suicide Bomber");
  }
  
  return Plugin_Continue;
}

/*
* Player Death
*/
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  //Check to see if spawn protection is on, if so, no explosion
  if (isSpawnProtection)
    return Plugin_Continue;
  
  //Get client and attacker
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
  new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
  
  //If death was not a suicide, ignore it
  if (client != attacker)
    return Plugin_Continue; 
  
  //If this player was killed by bomb, then simply change the attacker
  if (diedByBomb[client] != -1) {
    //This player should die by suicide bomber
    SetEventInt(event, "attacker", GetClientUserId(diedByBomb[client]));
    SetEventString(event, "weapon", "inferno"); //for flames
    --numKilledPlayers[diedByBomb[client]];
    
    //Check if this was last person to die
    //Reset bomb carrier if last CT to die 
    if (numKilledPlayers[diedByBomb[client]] == 0) {
      new bombCarrierIndex = FindValueInArray(bombCarriers, diedByBomb[client]);
      RemoveFromArray(bombCarriers, bombCarrierIndex);
      isBombEquipedByPlayer[diedByBomb[client]] = false;
    }
    
    //Fix suicide penalties
    SetEntProp(client, Prop_Data, "m_iFrags", GetEntProp(client, Prop_Data, "m_iFrags") + 1);
    CS_SetClientContributionScore(client, CS_GetClientContributionScore(client) + 2);
    
    //Reset died by bomb for this client
    diedByBomb[client] = -1;
    
    return Plugin_Continue;
  }
  
  //Check to see if this player was a bomb carrier
  new bombCarrierIndex = FindValueInArray(bombCarriers, client); 
  
  if (bombCarrierIndex == -1) //if this was not bomb carrier, ignore
    return Plugin_Continue;
  
  
  // ***** This player has the bomb! *****
  
  //Destory the bomb entity
  if (IsValidEntity(bombEntIndex[client]))
    AcceptEntityInput(bombEntIndex[client],"kill"); 
  
  //Get death position of suicider bomber
  new Float:suicide_bomber_vec[3];
  GetClientAbsOrigin(client, suicide_bomber_vec);
   
  //Get players team and friendly fire information
  new Handle:friendlyfire = FindConVar("mp_friendlyfire");
  new bool:ffON = GetConVarBool(friendlyfire);
  new enemyTeam = 3; //CT is the enemy team
  
  //For each alive CT
  new iMaxClients = GetMaxClients();
  numKilledPlayers[client] = 0; //reset kills by bomb to 0
  new deathList[MAXPLAYERS+1]; //store players that this bomb kills

  for (new i = 1; i <= iMaxClients; ++i)
  {
    //Check that client is a real player who is alive and is a CT
    if (IsClientInGame(i) && IsPlayerAlive(i) )
    {
      //Allow hurt enemies unless FF is on
      if (ffON || GetClientTeam(i) == enemyTeam) {
        new Float:ct_vec[3];
        GetClientAbsOrigin(i, ct_vec);

        new Float:distance = GetVectorDistance(ct_vec, suicide_bomber_vec, false);
        
        //If CT was in explosion radius, damage or kill them
        //Formula used: damage = 200 - (d/2)
        new damage = RoundToFloor(200.0 - (distance / 2.0));
        
        if (damage <= 0) //this player was not damaged 
          continue;
        
        //Damage the surrounding players
        new curHP = GetClientHealth(i);
        if (curHP - damage <= 0) {
          diedByBomb[i] = client; //client killed this 'i' target
          deathList[numKilledPlayers[client]] = i;
          ++numKilledPlayers[client];
        }
        else { //Survivor
          SetEntityHealth(i, curHP - damage);
          IgniteEntity(i, 5.0);
        }
      }
    }
  }

  new tempNumKilledPlayers = numKilledPlayers[client]; //locally cache the global var as it will change shortly
  
  //Get suicide bomber name
  new String:bombername[MAX_NAME_LENGTH+1];
  GetClientName(client, bombername, sizeof(bombername));
  
  if (tempNumKilledPlayers == 0)
    CPrintToChatAll("%s%t", PREFIX, "Suicide Bomber No Kills", bombername);
  else
    CPrintToChatAll("%s%t", PREFIX, "Suicide Bomber Got Kills", bombername, tempNumKilledPlayers);
    
  //Play explosion sounds
  EmitSoundToAllAny(EXPLOSION_SOUND_PATH, client, SNDCHAN_USER_BASE, SNDLEVEL_RAIDSIREN);
  TE_SetupExplosion(suicide_bomber_vec, g_ExplosionSprite, 10.0, 1, 0, 250, 5000);
  TE_SendToAll();
  
  //If no players died, reset bomb carrier
  if (tempNumKilledPlayers == 0) {
    //bombCarrierIndex is already defined above
    RemoveFromArray(bombCarriers, bombCarrierIndex);
    isBombEquipedByPlayer[client] = false;
  }
  else {
    //Kill all players on death list
    for (new i = 0; i < tempNumKilledPlayers; ++i) {
      ForcePlayerSuicide(deathList[i]);
    }
  }
  
  return Plugin_Continue;
}

/*
* Bomb Drop
*/
public Action:Event_BombDrop(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
    
  //Save bomb ent index
  bombEntIndex[client] = GetEventInt(event, "entindex");
  
  //Remove glow from carrier
  set_rendering(client);
  
  //Dont remove bomb carrier just yet set it to being no longer equiped
  isBombEquipedByPlayer[client] = false;
  
  //Remove this player as original carrier (no longer required)
  new originalCarrierIndex = FindValueInArray(originalCarriers, client);
  RemoveFromArray(originalCarriers, originalCarrierIndex);
  
  return Plugin_Continue;
}

/*
* Bomb Pick up
*/
public Action:Event_BombPickUp(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;

  new client = GetClientOfUserId(GetEventInt(event, "userid"));
 
  //This is a new bomb carrier, set em up
  PushArrayCell(bombCarriers, client);
  isBombEquipedByPlayer[client] = true;
  
  new isOriginalCarrier = FindValueInArray(originalCarriers, client);
  
  //Show instructions to this user if they aren't the original carrier
  //Needed to avoid duplicate message
  if (isOriginalCarrier == -1)
    CPrintToChat(client, "%s%t", PREFIX, "You Picked Up Suicide Bomb");
    
  //Add a glow to bomb carrier
  set_rendering(client, FX:FxDistort, GetConVarInt(g_highlightPlayer_RED), GetConVarInt(g_highlightPlayer_GREEN), GetConVarInt(g_highlightPlayer_BLUE), Render:RENDER_TRANSADD, 255);
    
  return Plugin_Continue;
}

/*
* Bomb Pick up Pre
*/
public Action:Event_BombPickUpPre(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;

  new client = GetClientOfUserId(GetEventInt(event, "userid"));
  
  //Check if client is bot and bot bomb is disabled
  //If so, disable bomb pickup
  if (IsFakeClient(client) && !GetConVarBool(g_bots_can_have_bomb))
    return Plugin_Handled;
  
  return Plugin_Continue;    
}

//Readd glow to bomb carrier
public Action:ReAddRedGlow(Handle:timer, client)
{
  //Check that this client is still in the game
  if (!IsClientInGame(client) || !IsPlayerAlive(client) ) {
    return;
  }
  
  //Check that player still has bomb
  new c4 = GetPlayerWeaponSlot(client, BOMB_SLOT);
  
  if (c4 != -1)
    set_rendering(client, FX:FxDistort, GetConVarInt(g_highlightPlayer_RED), GetConVarInt(g_highlightPlayer_GREEN), GetConVarInt(g_highlightPlayer_BLUE), Render:RENDER_TRANSADD, 255); //Add a glow to bomb carrier
}

/*
* Turn off spawn protection bool
*/
public Action:TurnOffSpawnProtectoon(Handle:timer)
{
  isSpawnProtection = false;
}

/*
* Needed for glow
*/
stock set_rendering(index, FX:fx=FxNone, r=255, g=255, b=255, Render:render=Normal, amount=255)
{
  SetEntProp(index, Prop_Send, "m_nRenderFX", _:fx, 1);
  SetEntProp(index, Prop_Send, "m_nRenderMode", _:render, 1);  
  SetEntData(index, RenderOffs, r, 1, true);
  SetEntData(index, RenderOffs + 1, g, 1, true);
  SetEntData(index, RenderOffs + 2, b, 1, true);
  SetEntData(index, RenderOffs + 3, amount, 1, true);  
}

/*
* Bind button to suicide
*/
public Action:OnPlayerRunCmd(client, &buttons)
{
  if (!isEnabled) 
      return Plugin_Continue;
    
  if (IsClientInGame(client) && IsPlayerAlive(client)) {
    
    //Ensure client is a bomb carrier and has bomb equiped
    new isBombCarrier = FindValueInArray(bombCarriers, client);
    
    //Return if not bomb carrier or not equiped
    if (isBombCarrier == -1 || !isBombEquipedByPlayer[client])
      return Plugin_Continue;
  
    new weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    
    //Return if invalid weapon entity
    if (weapon == -1)
      return Plugin_Continue;
    
    decl String:weaponName[64];
    GetEdictClassname(weapon, weaponName, sizeof(weaponName));

    if (buttons & IN_USE)
    {
      if(!StrEqual(weaponName, "weapon_c4")) {
        if (showUseErrorMessage[client]) {
        CPrintToChat(client, "%s%t", PREFIX, "Must Equip C4");
        showUseErrorMessage[client] = false;
        CreateTimer(1.0, ReenableMessages, client);
        }
        return Plugin_Continue;
      }
    
      if (isSpawnProtection) {
        if (showUseErrorMessage[client]) {
          //Let them know its too early
          CPrintToChat(client, "%s%t", PREFIX, "Too Early Suicide");
          showUseErrorMessage[client] = false;
          CreateTimer(1.0, ReenableMessages, client);
        }
        return Plugin_Continue;
      }
    
      //Let player suicide
      ForcePlayerSuicide(client);
    }
  }

  return Plugin_Continue;
}

//Reenable use error message
public Action:ReenableMessages(Handle:timer, any:client)
{
  showUseErrorMessage[client] = true;
}