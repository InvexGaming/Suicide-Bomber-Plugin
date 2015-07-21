#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include "colors_csgo.inc"
#include "emitsoundany.inc"

/*
* Plugin Information - Please do not change this
*/
public Plugin:myinfo =
{
  name        = "Suicide Bomber",
  author      = "Invex | Byte",
  description = "Disables bomb sites and allows bomb carrier to suicide to kill all players around them.",
  version     = "1.00",
  url         = "http://www.invexgaming.com.au"
};

//Definitions
#define BOMB_SLOT 4
#define EXPLOSION_SOUND "invex_gaming/misc/wtfboom_scream.mp3"
#define VIP_ENTRIES 3

new String:PREFIX[] = "[{olive}SuicideBomber{default}] ";
new bombCarrier = -1;
new bool:isBombEquipedByPlayer = false;
new bombEntIndex = -1;
new numKilledPlayers = 0;
new bool:bombkilledplayers[MAXPLAYERS+1] = {false, ...};
new bool:isSpawnProtection = false;
new bool:showUseErrorMessage = true;
new originalCarrier = -1;

//Booleans
new bool:isEnabled;

//Handles
new Handle:g_suicide_bomber_enabled = INVALID_HANDLE;

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
  g_suicide_bomber_enabled = CreateConVar("sm_suicide_bomber_enabled", "1", "Enable Suicide Bomber Plugin (0 off, 1 on, def. 1)");

  //Event hooks
  HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
  HookEvent("round_start", Event_RoundStart);
  HookEvent("bomb_dropped", Event_BombDrop);
  HookEvent("bomb_pickup", Event_BombPickUp);
  
  //Set random number seed
  SetRandomSeed(GetTime());
  
  //Enable status hook
  HookConVarChange(g_suicide_bomber_enabled, ConVarChange_enabled);
  
  //Find render offs
  RenderOffs = FindSendPropOffs("CBasePlayer", "m_clrRender");
  
  //Set Variable Values
  isEnabled = true;
}

/*
* On Map Start
*/
public OnMapStart()
{
  if (!isEnabled) 
    return;
  
  //Precache sounds
  AddFileToDownloadsTable("sound/invex_gaming/misc/wtfboom_scream.mp3");
  PrecacheSoundAny(EXPLOSION_SOUND);
  
  //Precache materials
  g_ExplosionSprite = PrecacheModel("sprites/sprite_flames.vmt");
  
  //Remove all real bomb sites
  new iEnt = -1;
  while((iEnt = FindEntityByClassname(iEnt, "func_bomb_target")) != -1) //Find bombsites
  {
    AcceptEntityInput(iEnt,"kill"); //Destroy the entity
  }
  
  //Create a fake bomb site
  //This allows bomb to show up on radar
  new customBombSite = CreateEntityByName("func_bomb_target");
  DispatchSpawn(customBombSite);
  
  //Disable the bomb distribution cvar
  //We will handle distribution
  new Handle:mp_give_player_c4 = FindConVar("mp_give_player_c4");
  SetConVarInt(mp_give_player_c4, 0);

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
  
  //Set spawn protection to be on
  isSpawnProtection = true;
  CreateTimer(15.0, TurnOffSpawnProtectoon);
  
  //Get terrorist list
  new terroristList[MAXPLAYERS*VIP_ENTRIES];
  new iCount = 0;
  
  for (new i = 1; i <= MaxClients; ++i) { 
    if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
      
      //Check if VIP
      new isVIP = CheckCommandAccess(i, "", ADMFLAG_CUSTOM3);
      new numEntries = 1;
      
      //VIP players are more likely to get bomb 
      if (isVIP)
        numEntries = VIP_ENTRIES;
      
      //Add entries for this player
      for (new j = 0; j < numEntries; ++j) {
        terroristList[iCount] = i;
        ++iCount; 
      } 
    }
  }
  
  if (iCount == 0) //no terrorists
    return Plugin_Continue;
  
  //Generate a random number
  new rand = GetRandomInt(0, iCount - 1);
  
  //Set original carrier
  originalCarrier = terroristList[rand];
  
  //Give 1 terrorist C4
  GivePlayerItem(originalCarrier, "weapon_c4");
  
  //Readd colour after 15 seconds, needed due to spawn protection
  CreateTimer(15.2, ReAddRedGlow, originalCarrier, originalCarrier);
  
  //Let them know!
  CPrintToChat(originalCarrier, "%s%t", PREFIX, "You Are Suicide Bomber");
  
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
  if (bombkilledplayers[client]) {
    //This player should die by suicide bomber
    SetEventInt(event, "attacker", GetClientUserId(bombCarrier));
    SetEventString(event, "weapon", "inferno"); //for flames
    bombkilledplayers[client] = false;
    --numKilledPlayers;
    
    //Check if this was last person to die
    //Reset bomb carrier if last CT to die 
    if (numKilledPlayers == 0) {
      bombCarrier = -1;
      isBombEquipedByPlayer = false;
    }
    
    //Fix suicide penalties
    SetEntProp(client, Prop_Data, "m_iFrags", GetEntProp(client, Prop_Data, "m_iFrags") + 1);
    CS_SetClientContributionScore(client, CS_GetClientContributionScore(client) + 2);
    
    return Plugin_Continue;
  }
  
  if (bombCarrier == -1 || client != bombCarrier) //if this was not bomb carrier, ignore
    return Plugin_Continue;
  
  //This player has the bomb!
  
  //Destory the bomb entity
  if (IsValidEntity(bombEntIndex))
    AcceptEntityInput(bombEntIndex,"kill"); 
  
  //Get death position
  new Float:suicide_bomber_vec[3];
  GetClientAbsOrigin(client, suicide_bomber_vec);
   
  //Get players team
  new Handle:friendlyfire = FindConVar("mp_friendlyfire");
  new bool:ffON = GetConVarBool(friendlyfire);
  new enemyTeam = 3; //CT is the enemy team
  
  //For each alive CT
  new iMaxClients = GetMaxClients();
  numKilledPlayers = 0;
  new deathList[MAXPLAYERS+1]; //store players to kill

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
        
        //If CT was in explosion radius (kill them)
        if (distance <= 200) {
          bombkilledplayers[i] = true;
          deathList[numKilledPlayers] = i;
          ++numKilledPlayers;
        }
        else if (distance <= 450) { //damage them slightly
          new damage = 25;
          if (distance <= 300)
            damage = 50;
          
          //Damage the surrounding players
          new curHP = GetClientHealth(i);
          if (curHP - damage <= 0) {
            bombkilledplayers[i] = true;
            deathList[numKilledPlayers] = i;
            ++numKilledPlayers;
          }
          else { //Survivor
            SetEntityHealth(i, curHP - damage);
            IgniteEntity(i, 2.2)
          }
        }
      }
    }
  }

  new tempNumKilledPlayers = numKilledPlayers; //locally cache the global var
  
  //Get suicide bomber name
  new String:bombername[MAX_NAME_LENGTH+1];
  GetClientName(client, bombername, sizeof(bombername));
  
  if (tempNumKilledPlayers == 0)
    CPrintToChatAll("%s%t", PREFIX, "Suicide Bomber No Kills", bombername);
  else
    CPrintToChatAll("%s%t", PREFIX, "Suicide Bomber Got Kills", bombername, tempNumKilledPlayers);
    
  //Play explosion sounds
  EmitSoundToAllAny(EXPLOSION_SOUND, client, SNDCHAN_USER_BASE, SNDLEVEL_RAIDSIREN);
  TE_SetupExplosion(suicide_bomber_vec, g_ExplosionSprite, 10.0, 1, 0, 250, 5000);
  TE_SendToAll();
  
  //If no players died, reset bomb carrier
  if (tempNumKilledPlayers == 0) {
    bombCarrier = -1;
    isBombEquipedByPlayer = false;
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
  bombEntIndex = GetEventInt(event, "entindex");
  
  //Remove glow from previous carrier
  set_rendering(client);
  
  //Dont bomb carrier but set bool
  isBombEquipedByPlayer = false;
  
  //No original carrier needed anymore
  originalCarrier = -1;
  
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
 
  //Set new bomb carrier
  bombCarrier = client;
  isBombEquipedByPlayer = true;
  
  //Show instructions to this user in case they dont know
  if (client != originalCarrier)
    CPrintToChat(client, "%s%t", PREFIX, "You Picked Up Suicide Bomb");
    
  //Add a glow to bomb carrier
  set_rendering(client, FX:FxDistort, 255, 0, 0, Render:RENDER_TRANSADD, 255);
    
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
    set_rendering(client, FX:FxDistort, 255, 0, 0, Render:RENDER_TRANSADD, 255); //Add a glow to bomb carrier
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
* Bind 'k' to suicide
*/
public OnGameFrame()
{
  if (!isEnabled) 
    return;
  
  new iMaxClients = GetMaxClients();
  
  for (new i = 1; i <= iMaxClients; ++i)
  {
    if (IsClientInGame(i) && IsPlayerAlive(i) && i == bombCarrier && isBombEquipedByPlayer)
    {
      new weapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
      
      //Return if invalid entity
      if (weapon == -1)
        return;
      
      decl String:weaponName[64];
      GetEdictClassname(weapon, weaponName, sizeof(weaponName));
  
      new cl_buttons = GetClientButtons(i);
      if (cl_buttons & IN_USE)
      {
        if(!StrEqual(weaponName, "weapon_c4")) {
          if (showUseErrorMessage) {
            CPrintToChat(i, "%s%t", PREFIX, "Must Equip C4");
            showUseErrorMessage = false;
            CreateTimer(1.0, ReenableMessages);
          }
          return;
        }
      
        if (isSpawnProtection) {
          if (showUseErrorMessage) {
            //Let them know its too early
            CPrintToChat(i, "%s%t", PREFIX, "Too Early Suicide");
            showUseErrorMessage = false;
            CreateTimer(1.0, ReenableMessages);
          }
          return;
        }
      
        //Let player suicide
        ForcePlayerSuicide(i);
      }
    }
  }
}

//Reenable use error message
public Action:ReenableMessages(Handle:timer)
{
  showUseErrorMessage = true;
}