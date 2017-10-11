-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

OOB_MSGTYPE_APPLYINIT = "applyinit";

function onInit()
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_APPLYINIT, handleApplyInit);

	ActionsManager.registerModHandler("init", modRoll);
	ActionsManager.registerResultHandler("init", onResolve);
end

function handleApplyInit(msgOOB)
	local rSource = ActorManager.getActor(msgOOB.sSourceType, msgOOB.sSourceNode);
	local nTotal = tonumber(msgOOB.nTotal) or 0;

	DB.setValue(ActorManager.getCTNode(rSource), "initresult", "number", nTotal);
end

function notifyApplyInit(rSource, nTotal)
	if not rSource then
		return;
	end
	
	local msgOOB = {};
	msgOOB.type = OOB_MSGTYPE_APPLYINIT;
	
	msgOOB.nTotal = nTotal;

	local sSourceType, sSourceNode = ActorManager.getTypeAndNodeName(rSource);
	msgOOB.sSourceType = sSourceType;
	msgOOB.sSourceNode = sSourceNode;

	Comm.deliverOOBMessage(msgOOB, "");
end

function getRoll(rActor, bSecretRoll, rItem)
	local rRoll = {};
	rRoll.sType = "init";
	rRoll.aDice = { "d" .. DataCommonADND.nDefaultInitiativeDice };
	rRoll.nMod = 0;
	
	rRoll.sDesc = "[INIT]";
	
	rRoll.bSecret = bSecretRoll;

	-- Determine the modifier and ability to use for this roll
	local sAbility = nil;
	local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);
    if nodeActor then
        if rItem then
            rRoll.nMod =  rItem.nInit;
            rRoll.sDesc = rRoll.sDesc .. " [MOD:" .. rItem.sName .. "]";
            if (rItem.nodeSpell) then
                applySpellCastingConcentration(nodeActor,rItem.nodeSpell);
            end
        elseif sActorType == "pc" then
            rRoll.nMod = DB.getValue(nodeActor, "initiative.total", 0);
--			sAbility = "dexterity";
        else
            local nMod = DB.getValue(nodeActor, "initiative.total", 0);
            if nMod == 0 then 
                nMod = DB.getValue(nodeActor, "init", 0);
            end
            rRoll.nMod = nMod;
        end
    end
    
--	if sAbility and sAbility ~= "" and sAbility ~= "dexterity" then
--		local sAbilityEffect = DataCommon.ability_ltos[sAbility];
--		if sAbilityEffect then
--			rRoll.sDesc = rRoll.sDesc .. " [MOD:" .. sAbilityEffect .. "]";
--		end
--	end
	
	return rRoll;
end

function applySpellCastingConcentration(nodeChar,nodeSpell)
    if not string.match(nodeChar.getPath(),"^combattracker") then
        nodeChar = CharManager.getCTNodeByNodeChar(nodeChar);
    end
    -- if not in the combat tracker bail
    if not nodeChar then
        return;
    end

    -- need to do some error checking to make sure we only add it once
    -- verify existing "effect_source" isn't the same as this one.
    local bFound = false;
    for _,nodeEffect in pairs(DB.getChildren(nodeChar, "effects")) do
        local sSource = DB.getValue(nodeEffect,"source_name","");
        if (sSource == nodeSpell.getPath()) then
            bFound = true;
            break;
        end
    end -- for item's effects list
    
    if bFound then
        return;
    end
    
    local sSpellName = DB.getValue(nodeSpell,"name","");
    local rEffect = {};
    local sEffectString = "(C)";
    rEffect.nDuration = 1;
    rEffect.sName = "Casting " .. sSpellName .. "; " .. sEffectString;
    rEffect.sLabel = sEffectString;
    rEffect.sUnits = "rnd";
    rEffect.nInit = 0;
    rEffect.sSource = nodeChar.getPath();
    rEffect.nGMOnly = 0;
    rEffect.sApply = "";
    EffectManager.addEffect("", "", nodeChar, rEffect, true);
end

function performRoll(draginfo, rActor, bSecretRoll, rItem)
	local rRoll = getRoll(rActor, bSecretRoll, rItem);
	
	ActionsManager.performAction(draginfo, rActor, rRoll);
end

function modRoll(rSource, rTarget, rRoll)
	local bADV = false;
	local bDIS = false;
	if rRoll.sDesc:match(" %[ADV%]") then
		bADV = true;
		rRoll.sDesc = rRoll.sDesc:gsub(" %[ADV%]", "");
	end
	if rRoll.sDesc:match(" %[DIS%]") then
		bDIS = true;
		rRoll.sDesc = rRoll.sDesc:gsub(" %[DIS%]", "");
	end

	if rSource then
		-- Determine ability used
		local sActionStat = nil;
		local sModStat = string.match(rRoll.sDesc, "%[MOD:(%w+)%]");
		if sModStat then
			sActionStat = DataCommon.ability_stol[sModStat];
		end
		if not sActionStat then
			sActionStat = "dexterity";
		end
		
		-- Determine general effect modifiers
		local bEffects = false;
		local aAddDice, nAddMod, nEffectCount = EffectManager5E.getEffectsBonus(rSource, {"INIT"});
        
		if nEffectCount > 0 then
			bEffects = true;
			for _,vDie in ipairs(aAddDice) do
				if vDie:sub(1,1) == "-" then
					table.insert(rRoll.aDice, "-p" .. vDie:sub(3));
				else
					table.insert(rRoll.aDice, "p" .. vDie:sub(2));
				end
			end
			rRoll.nMod = rRoll.nMod + nAddMod;
		end
		
		-- Get ability effect modifiers
		local nBonusStat, nBonusEffects = ActorManager2.getAbilityEffectsBonus(rSource, sActionStat);
		if nBonusEffects > 0 and nBonusStat ~= 0 then
			bEffects = true;
			rRoll.nMod = rRoll.nMod + nBonusStat;
		end
		
		-- Get condition modifiers
		if EffectManager5E.hasEffectCondition(rSource, "ADVINIT") then
			bADV = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "DISINIT") then
			bDIS = true;
			bEffects = true;
		end
		
		-- Not done in AD&D -celestian
		-- -- Since initiative is a Dexterity check, do all those checks as well
		-- --local aCheckFilter = { "dexterity" };
		-- -- Dexterity check modifiers
		-- local aDexCheckAddDice, nDexCheckAddMod, nDexCheckEffectCount = EffectManager5E.getEffectsBonus(rSource, {"CHECK"}, false, aCheckFilter);
		-- if (nDexCheckEffectCount > 0) then
			-- bEffects = true;
			-- for _,vDie in ipairs(aDexCheckAddDice) do
				-- if vDie:sub(1,1) == "-" then
					-- table.insert(rRoll.aDice, "-p" .. vDie:sub(3));
				-- else
					-- table.insert(rRoll.aDice, "p" .. vDie:sub(2));
				-- end
				-- table.insert(aAddDice, vDie)
			-- end
			-- rRoll.nMod = rRoll.nMod + nDexCheckAddMod;
			-- nAddMod = nAddMod + nDexCheckAddMod;
		-- end
		
		-- Dexterity check conditions
		if EffectManager5E.hasEffectCondition(rSource, "ADVCHK") then
			bADV = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "ADVCHK", aCheckFilter)) > 0 then
			bADV = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "DISCHK") then
			bDIS = true;
			bEffects = true;
		elseif #(EffectManager5E.getEffectsByType(rSource, "DISCHK", aCheckFilter)) > 0 then
			bDIS = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "Frightened") then
			bDIS = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "Intoxicated") then
			bDIS = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "Poisoned") then
			bDIS = true;
			bEffects = true;
		end
		if EffectManager5E.hasEffectCondition(rSource, "Encumbered") then
			bEffects = true;
			bDIS = true;
		end

		-- Get exhaustion modifiers
		local nExhaustMod, nExhaustCount = EffectManager5E.getEffectsBonus(rSource, {"EXHAUSTION"}, true);
		if nExhaustCount > 0 then
			bEffects = true;
			if nExhaustMod >= 1 then
				bDIS = true;
			end
		end
		
		-- If effects happened, then add note
		if bEffects then
			local sEffects = "";
			local sMod = StringManager.convertDiceToString(aAddDice, nAddMod, true);
			if sMod ~= "" then
				sEffects = "[" .. Interface.getString("effects_tag") .. " " .. sMod .. "]";
			else
				sEffects = "[" .. Interface.getString("effects_tag") .. "]";
			end
			rRoll.sDesc = rRoll.sDesc .. " " .. sEffects;
		end
	end
	
	ActionsManager2.encodeAdvantage(rRoll, bADV, bDIS);
end

function onResolve(rSource, rTarget, rRoll)
	ActionsManager2.decodeAdvantage(rRoll);

	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);
	Comm.deliverChatMessage(rMessage);
	
	local nTotal = ActionsManager.total(rRoll);
	notifyApplyInit(rSource, nTotal);
end
