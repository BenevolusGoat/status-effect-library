local Mod = Epiphany

local VERSION = 1
local game = Game()

local DEBUG_PRINT = false

local CACHED_CALLBACKS
local CACHED_STATUS_FLAGS
local CACHED_STATUS_FLAGS_REVERSE
local CACHED_CONFIG
local CACHED_MOD_CALLBACKS

local function InitMod()
	---Holds information about all active status effects
	---@class StatusEffects
	---@field Flags StatusFlag
	---@field NumStatusesActive integer
	---@field NumIconsActive integer
	---@field StatusEffectData {[string]: StatusEffectData}

	---Holds information about a single status effect
	---@class StatusEffectData
	---@field Countdown integer
	---@field Source EntityRef
	---@field Icon Sprite?
	---@field Color Color?
	---@field CustomData table

	---@class StatusCallback
	---@field Priority integer
	---@field Function function
	---@field Args any[]

	---@class StatusConfig
	---@field Icon Sprite?
	---@field Color Color?
	---@field IgnoreFlags EntityFlag?
	---@field CustomTargetCheck boolean?

	---@alias StatusFlag integer

	local StatusEffectLibrary = RegisterMod(("[%s] Status Effect Library"):format(Mod.Name), 1)
	StatusEffectLibrary.Version = VERSION

	StatusEffectLibrary.BOSS_STATUS_EFFECT_COOLDOWN = 240

	---@type Color
	local FROZEN_COLOR = Color(0.8, 0.8, 0.8, 1, 0.3, 0.5, 0.8)
	FROZEN_COLOR:SetColorize(1, 1, 1, 0.5)

	local OFFSET = 40/255

	StatusEffectLibrary.StatusColor = {
		FROZEN = FROZEN_COLOR,
		PETRIFIED = Color(0.22, 0.22, 0.22, 1, OFFSET, OFFSET, OFFSET),
		CONFUSION = Color(0.5, 0.5, 0.5, 1, OFFSET, OFFSET, OFFSET),
		SLOW = Color(1, 1, 1.3, 1, OFFSET, OFFSET, OFFSET),
		MIDAS = Color(1.5, 1.5, 0.3, 1.0, OFFSET, OFFSET, OFFSET),
		FRIENDLY = Color(0.8, 0.8, 0.8, 1.0, 0.1, 0.1, 0.1),
		CHARM = Color(1.0, 0.0, 0.8, 1.0, OFFSET, OFFSET, OFFSET),
		FEAR = Color(0.5, 0.1, 0.5, 1.0, 0.0, 0.0, 0.0),
	}

	---@type {[string]: StatusFlag}
	StatusEffectLibrary.StatusFlag = CACHED_STATUS_FLAGS or {}

	---@type {[string]: string}
	StatusEffectLibrary.BitflagToStatusFlag = CACHED_STATUS_FLAGS_REVERSE or {}

	StatusEffectLibrary.BlacklistParentChildDistribution = {
		[EntityType.ENTITY_CLUTCH] = true,
		[EntityType.ENTITY_CLICKETY_CLACK] = true
	}

	StatusEffectLibrary.NUM_STATUS_EFFECTS = 0

	---@type {[string]: StatusConfig}
	StatusEffectLibrary.StatusConfig = CACHED_CONFIG or {}

	---@type table<ModCallbacks, function[]>
	StatusEffectLibrary.AddedCallbacks = {} -- for any vanilla callback functions added by this library

	StatusEffectLibrary.Callbacks = {}

	---@type table<string, StatusCallback[]>
	StatusEffectLibrary.Callbacks.RegisteredCallbacks = game:GetFrameCount() == 0 and CACHED_CALLBACKS or {}
	StatusEffectLibrary.AddedCallbacks = game:GetFrameCount() == 0 and CACHED_MOD_CALLBACKS or StatusEffectLibrary.AddedCallbacks

	StatusEffectLibrary.Version = VERSION

	return StatusEffectLibrary
end

local function InitFunctions()
	--#region Constants

	---@enum StatusEffectCallbackID
	StatusEffectLibrary.Callbacks.ID = {
		-- Called during NPC_UPDATE if any custom status effects are applied to an enemy or player
		-- - `self` - StatusEffectLibrary Mod Global
		-- - `entity` - The affected enemy/player. Will be EntityNPC/EntityPlayer appropriately
		-- - `statusEffects` - BigFlag of the applied status effects
		--
		-- An extra argument can be passed to limit the callback to a specific StatusFlag
		ENTITY_STATUS_EFFECT_UPDATE = "STATUSEFFECTLIBRARY_ENTITY_STATUS_EFFECT_UPDATE",

		-- Called after valid target check, but before a custom status effect is applied to an enemy or player
		-- - `self` - StatusEffectLibrary Mod Global
		-- - `entity` - The affected enemy/player. Will be EntityNPC/EntityPlayer appropriately
		-- - `statusEffect` - BigFlag of the status effect being applied
		-- - `customData` - Any custom data passed when AddStatusEffect was called
		--
		-- An extra argument can be passed to limit the callback to a specific StatusFlag
		-- Return any value other than `nil` to cancel adding the effect
		PRE_ADD_ENTITY_STATUS_EFFECT = "STATUSEFFECTLIBRARY_PRE_ADD_ENTITY_STATUS_EFFECT",

		-- Called after a custom status effect is applied to an enemy or player
		-- - `self` - StatusEffectLibrary Mod Global
		-- - `entity` - The affected enemy/player. Will be EntityNPC/EntityPlayer appropriately
		-- - `statusEffect` - BigFlag of the status effect being applied
		-- - `customData` - Any custom data passed when AddStatusEffect was called
		-- - `statusEffectData` - Data of the status effect being added
		--
		-- An extra argument can be passed to limit the callback to a specific StatusFlag
		POST_ADD_ENTITY_STATUS_EFFECT = "STATUSEFFECTLIBRARY_POST_ADD_ENTITY_STATUS_EFFECT",

		-- Called before a custom status effect is removed from an enemy or player
		-- - `self` - StatusEffectLibrary Mod Global
		-- - `entity` - The affected enemy/player. Will be EntityNPC/EntityPlayer appropriately
		-- - `statusEffect` - BigFlag of the status effect being applied
		-- - `statusEffectData` - Data of the status effect being removed
		--
		-- An extra argument can be passed to limit the callback to a specific StatusFlag
		PRE_REMOVE_ENTITY_STATUS_EFFECT = "STATUSEFFECTLIBRARY_PRE_REMOVE_ENTITY_STATUS_EFFECT",

		-- Called after a custom status effect is removed from an enemy or player
		-- - `self` - StatusEffectLibrary Mod Global
		-- - `entity` - The affected enemy/player. Will be EntityNPC/EntityPlayer appropriately
		-- - `statusEffect` - BigFlag of the status effect being applied
		-- - `statusEffectData` - Data of the status effect being removed
		--
		-- An extra argument can be passed to limit the callback to a specific StatusFlag
		POST_REMOVE_ENTITY_STATUS_EFFECT = "STATUSEFFECTLIBRARY_POST_REMOVE_ENTITY_STATUS_EFFECT"
	}

	for _, v in pairs(StatusEffectLibrary.Callbacks.ID) do
		if not StatusEffectLibrary.Callbacks.RegisteredCallbacks[v] then
			StatusEffectLibrary.Callbacks.RegisteredCallbacks[v] = {}
		end
	end

	StatusEffectLibrary.CallbackPriority = {
		HIGHEST = 0,
		HIGH = 10,
		NORMAL = 20,
		LOW = 30,
		LOWEST = 40,
	}

	--#endregion

	--#region Helper functions

	StatusEffectLibrary.Utils = {}

	function StatusEffectLibrary.Utils.Log(id, ...)
		local str = "[StatusEffectLibrary] [Status " .. id .. "]: ".. table.concat({...}, " ")
		print(str)
		Isaac.DebugString(str)
	end

	function StatusEffectLibrary.Utils.DebugLog(id, ...)
		if DEBUG_PRINT then
			StatusEffectLibrary.Utils.Log(id, ...)
		end
	end

	--Takes a dictionary and converts it into a list
	---@generic V
	---@param dict table<any, V>
	---@return V[]
	function StatusEffectLibrary.Utils.ToList(dict)
		local out = {}
		for _, v in pairs(dict) do
			out[#out + 1] = v
		end
		return out
	end

	---Returns true if the first agument contains the second argument
	---@generic flag : BitSet128 | integer | TearFlags
	---@param flags flag
	---@param checkFlag flag
	function StatusEffectLibrary.Utils.HasBitFlags(flags, checkFlag)
		if not checkFlag then
			error("BitMaskHelper: checkFlag is nil", 2)
		end
		return flags & checkFlag == checkFlag
	end

	---Returns true if the first argument contains any of the flags in the second argument. A looser version of HasBitFlags.
	---@generic flag : BitSet128 | integer | TearFlags
	---@param flags flag
	---@param checkFlag flag
	function StatusEffectLibrary.Utils.HasAnyBitFlags(flags, checkFlag)
		return flags & checkFlag > 0
	end

	---Adds the second argument bitflag to the first
	---@generic flag : BitSet128 | integer | TearFlags
	---@param flags flag
	---@param addFlag flag
	---@return flag
	function StatusEffectLibrary.Utils.AddBitFlags(flags, addFlag)
		flags = flags | addFlag
		return flags
	end

	---Removes the second argument bitflag from the first. If it doesn't have it, it will remain the same
	---@generic flag : BitSet128 | integer | TearFlags
	---@param flags flag
	---@param removeFlag flag
	---@return flag
	function StatusEffectLibrary.Utils.RemoveBitFlags(flags, removeFlag)
		flags = flags & ~removeFlag
		return flags
	end

	---Copies the properties of the provided `Sprite` object and returns a new one with the same properties
	---@param sprite Sprite
	---@return Sprite
	function StatusEffectLibrary.Utils.CopySprite(sprite)
		local copySprite = Sprite()

		if not sprite:IsLoaded() then
			return copySprite
		end

		copySprite:Load(sprite:GetFilename(), true)

		local anim = sprite:GetAnimation()
		local overlayAnim = sprite:GetOverlayAnimation()

		if anim == "" and overlayAnim == "" then
			return copySprite
		end

		--Auto-assigns FlipX, Scale, etc
		local s1Metatable = getmetatable(sprite)
		for key, value in pairs(s1Metatable.__propget) do
			copySprite[key] = value(sprite)
		end
		copySprite:SetFrame(anim, sprite:GetFrame())
		copySprite:SetOverlayFrame(overlayAnim, sprite:GetOverlayFrame())
		if REPENTOGON then
			copySprite:SetRenderFlags(sprite:GetRenderFlags())
		end
		if sprite:IsPlaying(anim) then
			copySprite:Play(anim)
		end
		if sprite:IsOverlayPlaying(overlayAnim) then
			copySprite:PlayOverlay(overlayAnim)
		end

		return copySprite
	end

	---Returns the duration multiplier given by Second Hand trinket
	---@return number
	function StatusEffectLibrary.Utils.GetSecondHandMultiplier()
		local players = REPENTOGON and PlayerManager.GetPlayers() or Isaac.FindByType(EntityType.ENTITY_PLAYER)
		local durationMult = 1
		---@param player EntityPlayer
		for _, player in ipairs(players) do
			local secondMult = player:ToPlayer():GetTrinketMultiplier(TrinketType.TRINKET_SECOND_HAND)
			durationMult = math.min(3, durationMult + secondMult)
		end
		return durationMult
	end

	function StatusEffectLibrary.Utils.DeepCopy(tab)
		if type(tab) ~= "table" then
			return tab
		end

		local final = setmetatable({}, getmetatable(tab))
		for i, v in pairs(tab) do
			final[i] = StatusEffectLibrary.Utils.DeepCopy(v)
		end

		return final
	end

	--#endregion

	--#region Custom Callbacks

	StatusEffectLibrary.CallbackHandlers = {
		[StatusEffectLibrary.Callbacks.ID.ENTITY_STATUS_EFFECT_UPDATE] = function(callbacks, entity, statusEffects)
			for i = 1, #callbacks do
				local limits = callbacks[i].Args
				local shouldFire = not limits[1] or StatusEffectLibrary.Utils.HasAnyBitFlags(statusEffects, limits[1])

				if shouldFire then
					local result = callbacks[i].Function(StatusEffectLibrary, entity, statusEffects)
					if result ~= nil then
						return result
					end
				end
			end
		end,
		[StatusEffectLibrary.Callbacks.ID.PRE_ADD_ENTITY_STATUS_EFFECT] = function(callbacks, entity, statusEffect, customData)
			for i = 1, #callbacks do
				local limits = callbacks[i].Args
				local shouldFire = not limits[1] or StatusEffectLibrary.Utils.HasBitFlags(statusEffect, limits[1])

				if shouldFire then
					local result = callbacks[i].Function(StatusEffectLibrary, entity, statusEffect, customData)
					if result ~= nil then
						return result
					end
				end
			end
		end,
		[StatusEffectLibrary.Callbacks.ID.POST_ADD_ENTITY_STATUS_EFFECT] = function(callbacks, entity, statusEffect)
			for i = 1, #callbacks do
				local limits = callbacks[i].Args
				local shouldFire = not limits[1] or StatusEffectLibrary.Utils.HasBitFlags(statusEffect, limits[1])

				if shouldFire then
					callbacks[i].Function(StatusEffectLibrary, entity, statusEffect)
				end
			end
		end,
		[StatusEffectLibrary.Callbacks.ID.PRE_REMOVE_ENTITY_STATUS_EFFECT] = function(callbacks, entity, statusEffect, statusEffectData)
			for i = 1, #callbacks do
				local limits = callbacks[i].Args
				local shouldFire = not limits[1] or StatusEffectLibrary.Utils.HasBitFlags(statusEffect, limits[1])

				if shouldFire then
					callbacks[i].Function(StatusEffectLibrary, entity, statusEffect, statusEffectData)
				end
			end
		end,
		[StatusEffectLibrary.Callbacks.ID.POST_REMOVE_ENTITY_STATUS_EFFECT] = function(callbacks, entity, statusEffect, statusEffectData)
			for i = 1, #callbacks do
				local limits = callbacks[i].Args
				local shouldFire = not limits[1] or StatusEffectLibrary.Utils.HasBitFlags(statusEffect, limits[1])

				if shouldFire then
					callbacks[i].Function(StatusEffectLibrary, entity, statusEffect, statusEffectData)
				end
			end
		end,
	}

	---@param id StatusEffectCallbackID
	---@param priority integer
	---@param func function
	---@param ... any
	function StatusEffectLibrary.Callbacks.AddPriorityCallback(id, priority, func, ...)
		local callbacks = StatusEffectLibrary.Callbacks.RegisteredCallbacks[id]
		local callback = {
			Priority = priority,
			Function = func,
			Args = { ... },
		}

		table.insert(callbacks, callback)
		table.sort(callbacks, function (a, b)
			return a.Priority < b.Priority
		end)
	end

	---@param id StatusEffectCallbackID
	---@param func function
	---@param ... any
	function StatusEffectLibrary.Callbacks.AddCallback(id, func, ...)
		StatusEffectLibrary.Callbacks.AddPriorityCallback(id, StatusEffectLibrary.CallbackPriority.NORMAL, func, ...)
	end

	---@param id StatusEffectCallbackID
	---@param func function
	function StatusEffectLibrary.Callbacks.RemoveCallback(id, func)
		local callbacks = StatusEffectLibrary.Callbacks.RegisteredCallbacks[id]
		for i = #callbacks, 1, -1 do
			if callbacks[i].Function == func then
				table.remove(callbacks, i)
			end
		end
	end

	---@param id StatusEffectCallbackID
	function StatusEffectLibrary.Callbacks.FireCallback(id, ...)
		local callbacks = StatusEffectLibrary.Callbacks.RegisteredCallbacks[id]
		if callbacks ~= nil then
			return StatusEffectLibrary.CallbackHandlers[id](callbacks, ...)
		end
	end

	--#endregion

	--#region Data Get functions

	---@param ent Entity
	---@return StatusEffects?
	function StatusEffectLibrary:GetStatusEffects(ent)
		local data = ent:GetData()
		return data.StatusEffectLibrary
	end

	---@param ent Entity
	---@param statusFlag StatusFlag
	---@return StatusEffectData?
	function StatusEffectLibrary:GetStatusEffectData(ent, statusFlag)
		local identifier = StatusEffectLibrary.BitflagToStatusFlag[statusFlag]
		if not identifier then return end
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects then return end
		local statusEffectData = statusEffects.StatusEffectData[identifier]
		return statusEffectData
	end

	--#endregion

	--#region Standard Status Callbacks

	---Automatically creates a bitflag for your status effects and assigns the `identifier` to the StatusFlag enumeration
	---@param identifier string
	---@param icon? Sprite #The icon to be rendered above the NPC. This will serve as a template, to which each NPC will receive a copy of the sprite
	---@param color? Color #The color the entity is set to while under the status effect
	---@param ignoreFlags? EntityFlag | integer #Any EntityFlag status effects this status effect should ignore when choosing whether to apply or not
	---@param customTargetCheck? boolean #Bypass the default check that runs before a status effect is applied
	function StatusEffectLibrary.RegisterStatusEffect(identifier, icon, color, ignoreFlags, customTargetCheck)
		local statusEffects = StatusEffectLibrary.Utils.ToList(StatusEffectLibrary.StatusFlag)
		table.sort(statusEffects)

		if StatusEffectLibrary.StatusConfig[identifier] then
			StatusEffectLibrary.Utils.Log(
				identifier,
				"Status effect with this identifier already exists, overwriting..."
			)
		else
			StatusEffectLibrary.StatusFlag[identifier] = 1 << #statusEffects
			StatusEffectLibrary.BitflagToStatusFlag[1 << #statusEffects] = identifier
		end
		StatusEffectLibrary.StatusConfig[identifier] = {
			Icon = icon,
			Color = color,
			IgnoreFlags = ignoreFlags,
			CustomTargetCheck = customTargetCheck
		}

		StatusEffectLibrary.NUM_STATUS_EFFECTS = StatusEffectLibrary.NUM_STATUS_EFFECTS + 1
		StatusEffectLibrary.Utils.DebugLog(
			identifier,
			"Registered with bitflag",
			StatusEffectLibrary.StatusFlag[identifier]
		)

		return StatusEffectLibrary.StatusConfig[identifier]
	end

	local tempBlacklist = {}

	---Add a status effect to the provided ent
	---
	---If the entity is part of a parent-child chain, will automatically repeat the process for said chain
	---@param ent Entity
	---@param statusFlag StatusFlag
	---@param duration integer
	---@param source EntityRef
	---@param color? Color #Provide a color manually for the status duration. This will override the default color, if any, associated with the status effect
	---@param customData? table #A table containing any number of varables you wish
	function StatusEffectLibrary:AddStatusEffect(ent, statusFlag, duration, source, color, customData)
		local identifier = StatusEffectLibrary.BitflagToStatusFlag[statusFlag]
		if not identifier then
			error(string.format("[StatusEffectLibrary] Status effect %s does not exist", statusFlag))
		end
		local statusConfig = StatusEffectLibrary.StatusConfig[identifier]
		if not statusConfig then return end
		if not StatusEffectLibrary:IsValidTarget(ent) and not statusConfig.CustomTargetCheck then
			return
		end

		customData = customData or {}
		local result = StatusEffectLibrary.Callbacks.FireCallback(
			StatusEffectLibrary.Callbacks.ID.PRE_ADD_ENTITY_STATUS_EFFECT,
			ent, statusFlag, customData
		)
		if result ~= nil then
			return
		end

		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects then
			statusEffects = {
				Flags = 0,
				NumStatusesActive = 0,
				NumIconsActive = 0,
				StatusEffectData = {}
			}
			ent:GetData().StatusEffectLibrary = statusEffects
			StatusEffectLibrary.Utils.DebugLog(identifier, "Initialized status effect data")
		end

		local durationMult = StatusEffectLibrary.Utils.GetSecondHandMultiplier()
		duration = math.floor(duration * durationMult)

		statusEffects.Flags = statusEffects.Flags | StatusEffectLibrary.StatusFlag[identifier]
		statusEffects.NumStatusesActive = statusEffects.NumStatusesActive + 1

		local statusEffectData = statusEffects.StatusEffectData[identifier]
		if not statusEffectData then
			statusEffects.StatusEffectData[identifier] = {
				Countdown = duration,
				Source = source,
				CustomData = customData
			}
			statusEffectData = statusEffects.StatusEffectData[identifier]
			StatusEffectLibrary.Utils.DebugLog(identifier, "Initialized status update data with duration of", duration)
		else
			statusEffectData.Countdown = duration
			StatusEffectLibrary.Utils.DebugLog(identifier, "Status Update data already initialized. Resetting duration to", duration)
			return
		end

		if not StatusEffectLibrary.BlacklistParentChildDistribution[ent.Type] or not tempBlacklist[GetPtrHash(ent)] then
			local parents = {}
			local children = {}
			local currentEnt = ent

			while currentEnt.Parent and not parents[GetPtrHash(currentEnt)] do
				parents[GetPtrHash(currentEnt)] = true
				currentEnt = currentEnt.Parent
			end

			while currentEnt.Child and not children[GetPtrHash(currentEnt)] do
				children[GetPtrHash(currentEnt)] = true
				tempBlacklist[GetPtrHash(currentEnt)] = true
				StatusEffectLibrary:AddStatusEffect(currentEnt, statusFlag, duration, source, color, StatusEffectLibrary.Utils.DeepCopy(customData))
				tempBlacklist[GetPtrHash(currentEnt)] = nil
				currentEnt = currentEnt.Child
			end
		end

		if ent:IsBoss() and not statusConfig.CustomTargetCheck then
			StatusEffectLibrary.Utils.DebugLog(identifier, "Entity is a boss. Starting status effect cooldown.")
			if REPENTOGON then
				ent:SetBossStatusEffectCooldown(StatusEffectLibrary.BOSS_STATUS_EFFECT_COOLDOWN)
			else
				ent:GetData().BossStatusEffectCooldown = StatusEffectLibrary.BOSS_STATUS_EFFECT_COOLDOWN
			end
		end

		if statusConfig.Icon
			and not statusEffectData.Icon
		then
			statusEffectData.Icon = StatusEffectLibrary.Utils.CopySprite(statusConfig.Icon)
			statusEffects.NumIconsActive = statusEffects.NumIconsActive + 1
			StatusEffectLibrary.Utils.DebugLog(identifier, "Icon added. Max number of icons is", statusEffects.NumIconsActive)
		end

		if color or statusConfig.Color then
			statusEffectData.Color = color or statusConfig.Color
			StatusEffectLibrary.Utils.DebugLog(identifier, "Color added")
		end

		StatusEffectLibrary.Callbacks.FireCallback(StatusEffectLibrary.Callbacks.ID.POST_ADD_ENTITY_STATUS_EFFECT,
		ent, statusFlag, customData, statusEffectData)
	end

	---@param ent Entity
	---@param statusFlag StatusFlag
	function StatusEffectLibrary:RemoveStatusEffect(ent, statusFlag)
		local identifier = StatusEffectLibrary.BitflagToStatusFlag[statusFlag]
		if not identifier then
			error("Status effect" .. statusFlag .. " does not exist")
		end
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects then return end

		local statusEffectData = StatusEffectLibrary:GetStatusEffectData(ent, statusFlag)
		if not statusEffectData then return end

		StatusEffectLibrary.Callbacks.FireCallback(
			StatusEffectLibrary.Callbacks.ID.PRE_REMOVE_ENTITY_STATUS_EFFECT,
			ent, statusFlag, statusEffectData
		)
		statusEffects.Flags = statusEffects.Flags & ~StatusEffectLibrary.StatusFlag[identifier]
		statusEffects.NumStatusesActive = statusEffects.NumStatusesActive - 1
		if statusEffectData.Icon then
			statusEffects.NumIconsActive = statusEffects.NumIconsActive - 1
		end
		statusEffects.StatusEffectData[identifier] = nil
		StatusEffectLibrary.Callbacks.FireCallback(
			StatusEffectLibrary.Callbacks.ID.POST_REMOVE_ENTITY_STATUS_EFFECT,
			ent, statusFlag, statusEffectData
		)
		StatusEffectLibrary.Utils.DebugLog(identifier, "Successfully removed status")
	end

	---@param ent Entity
	---@param statusFlag StatusFlag
	function StatusEffectLibrary:HasStatusEffect(ent, statusFlag)
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects then return false end
		return StatusEffectLibrary.Utils.HasAnyBitFlags(statusFlag, statusEffects.Flags)
	end

	---@param ent Entity
	function StatusEffectLibrary:ClearStatusEffects(ent)
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects then return end
		ent:GetData().StatusEffectLibrary = {
			Flags = 0,
			NumStatusesActive = 0,
			NumIconsActive = 0,
			StatusEffectData = {}
		}
	end

	--#endregion

	--#region Additional functions

	--Leaving it mostly vague so the effects can decide themselves most other factors on whether or not to apply statuses
	---@param ent Entity
	function StatusEffectLibrary:IsValidTarget(ent)
		if not ent:ToNPC() and not ent:ToPlayer() then
			return true
		end
		if ent:HasEntityFlags(EntityFlag.FLAG_NO_STATUS_EFFECTS) or not ent:IsActiveEnemy(false) then
			return false
		end
		if ent:IsBoss() then
			if REPENTOGON then
				return ent:GetBossStatusEffectCooldown() <= 0
			else
				return (ent:GetData().BossStatusEffectCooldown or 0) <= 0
			end
		end
		return true
	end

	---Returns the current countdown of the provided status effect. If the effect is not active, returns `0`
	---@param ent Entity
	---@param statusFlag StatusFlag
	---@return integer
	function StatusEffectLibrary:GetStatusEffectCountdown(ent, statusFlag)
		local statusEffectData = StatusEffectLibrary:GetStatusEffectData(ent, statusFlag)
		if not statusEffectData then return 0 end
		return statusEffectData.Countdown
	end

	---Sets the current countdown of the provided status effect. Does nothing if the status effect isn't active
	---@param ent Entity
	---@param statusFlag StatusFlag
	---@param countdown integer
	function StatusEffectLibrary:SetStatusEffectCountdown(ent, statusFlag, countdown)
		local statusEffectData = StatusEffectLibrary:GetStatusEffectData(ent, statusFlag)
		if not statusEffectData then return end
		statusEffectData.Countdown = countdown
	end

	---@param ent Entity
	---@param onlyIcon? boolean @Set to true to only detect status effects with an associated sprite
	---@param bypassIgnore? boolean @Check if you have any vanilla effects at all, bypassing custom status effects that ignore certain statuses
	function StatusEffectLibrary:HasAnyVanillaStatusEffect(ent, onlyIcon, bypassIgnore)
		local regularStatus = EntityFlag.FLAG_FREEZE
			| EntityFlag.FLAG_MIDAS_FREEZE
			| EntityFlag.FLAG_SHRINK
			| EntityFlag.FLAG_ICE
		local iconStatus = EntityFlag.FLAG_POISON
			| EntityFlag.FLAG_SLOW
			| EntityFlag.FLAG_CHARM
			| EntityFlag.FLAG_CONFUSION
			| EntityFlag.FLAG_FEAR
			| EntityFlag.FLAG_BLEED_OUT
			| EntityFlag.FLAG_MAGNETIZED
			| EntityFlag.FLAG_BAITED
			| EntityFlag.FLAG_WEAKNESS
			| EntityFlag.FLAG_BRIMSTONE_MARKED
			| EntityFlag.FLAG_BURN
		local vanillaEffects = onlyIcon and iconStatus or (regularStatus | iconStatus)
		local customEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if customEffects and bypassIgnore then
			for _, flag in ipairs(StatusEffectLibrary.StatusFlag) do
				if StatusEffectLibrary.StatusConfig[flag].IgnoreFlags and StatusEffectLibrary:HasStatusEffect(ent, flag) then
					vanillaEffects = vanillaEffects & ~StatusEffectLibrary.StatusConfig[flag].IgnoreFlags
				end
			end
		end
		return ent:HasEntityFlags(vanillaEffects)
	end

	---@param ent Entity
	function StatusEffectLibrary:HasAnyCustomStatusEffect(ent)
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects then return false end
		local curStatusEffects = statusEffects.Flags
		local allStatusEffects = 0
		for name, bitmask in pairs(StatusEffectLibrary.StatusFlag) do
			if name ~= "NUM_STATUS_EFFECTS" then
				allStatusEffects = allStatusEffects | bitmask
			end
		end
		return StatusEffectLibrary.HasAnyBitFlags(curStatusEffects, allStatusEffects)
	end

	--#endregion

	--#region Callback functions

	---@param ent Entity
	---@param offset Vector
	function StatusEffectLibrary.OnStatusEffectRender(_, ent, offset)
		if (REPENTOGON and ent:GetBossStatusEffectCooldown() > 0 or ent:GetData().BossStatusEffectCooldown)
		and DEBUG_PRINT
		then
			local num = REPENTOGON and ent:GetBossStatusEffectCooldown() or ent:GetData().BossStatusEffectCooldown
			local textPos = Isaac.WorldToRenderPosition(ent.Position) + Vector(-50, -50)
			Isaac.RenderText("Boss Cooldown: " .. tostring(num), textPos.X, textPos.Y, 1, 1, 1, 1)
		end
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if game:GetRoom():GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
			or not statusEffects
		then
			return
		end

		if ent:HasEntityFlags(EntityFlag.FLAG_ICE_FROZEN) then
			StatusEffectLibrary:ClearStatusEffects(ent)
			return
		end
		local renderPos = Isaac.WorldToRenderPosition(ent.Position + ent.PositionOffset) + offset
		if REPENTOGON then
			local sprite = ent:GetSprite()
			local nullFrame = sprite:GetNullFrame("OverlayEffect")
			if not nullFrame or not nullFrame:IsVisible() then
				return
			end
			local statusOffset = nullFrame ~= nil and nullFrame:GetPos() or Vector.Zero

			renderPos = renderPos + statusOffset
		else
			renderPos = renderPos - Vector(0, 35)
		end
		if StatusEffectLibrary:HasAnyVanillaStatusEffect(ent, true) then
			renderPos = renderPos - Vector(0, 24)
		end

		local iconIndex = 1
		for _, statusEffectData in pairs(statusEffects.StatusEffectData) do
			if statusEffectData.Icon then
				statusEffectData.Icon:Render(Vector((-8 * (statusEffects.NumIconsActive - 1)) + (16 * (iconIndex - 1)), 0) +
					renderPos)
				iconIndex = iconIndex + 1
				if Isaac.GetFrameCount() % 2 == 0
					and not game:IsPaused()
				then
					statusEffectData.Icon:Update()
				end
			end
		end
	end

	---@param npc Entity
	function StatusEffectLibrary:BossStatusEffectCooldown(npc)
		local data = npc:GetData()
		if npc:IsBoss()
			and StatusEffectLibrary:HasAnyVanillaStatusEffect(npc, false, true)
			and not REPENTOGON
			and not data.BossStatusEffectCooldown
		then
			npc:GetData().BossStatusEffectCooldown = StatusEffectLibrary.BOSS_STATUS_EFFECT_COOLDOWN
		end
		if data.BossStatusEffectCooldown then
			data.BossStatusEffectCooldown = data.BossStatusEffectCooldown - 1
			if data.BossStatusEffectCooldown <= 0 then
				data.BossStatusEffectCooldown = nil
			end
		end
	end

	---@param ent Entity
	function StatusEffectLibrary.OnStatusEffectUpdate(_, ent)
		StatusEffectLibrary:BossStatusEffectCooldown(ent)
		local statusEffects = StatusEffectLibrary:GetStatusEffects(ent)
		if not statusEffects or statusEffects.NumStatusesActive <= 0 then return end

		for identifier, statusEffectData in pairs(statusEffects.StatusEffectData) do
			statusEffectData.Countdown = statusEffectData.Countdown - 1
			if statusEffectData.Color then
				ent:SetColor(statusEffectData.Color, 2, 1, false, false)
			end
			if statusEffectData.Countdown == 0 then
				StatusEffectLibrary.Utils.DebugLog(identifier, "Effect expired.")
				local statusFlag = StatusEffectLibrary.StatusFlag[identifier]
				StatusEffectLibrary:RemoveStatusEffect(ent, statusFlag)
			end
		end
		local result = StatusEffectLibrary.Callbacks.FireCallback(
			StatusEffectLibrary.Callbacks.ID.ENTITY_STATUS_EFFECT_UPDATE,
			ent:ToNPC() or ent:ToPlayer(),
			statusEffects.Flags
		)

		return result
	end

	-- Unregister previous callbacks
	for callback, funcs in pairs(StatusEffectLibrary.AddedCallbacks) do
		for i = 1, #funcs do
			StatusEffectLibrary:RemoveCallback(callback, funcs[i])
		end
	end

	local function AddPriorityCallback(callback, priority, func, arg)
		StatusEffectLibrary:AddPriorityCallback(callback, priority, func, arg)
		if not StatusEffectLibrary.AddedCallbacks[callback] then
			StatusEffectLibrary.AddedCallbacks[callback] = {}
		end
		table.insert(StatusEffectLibrary.AddedCallbacks[callback], func)
	end

	local function AddCallback(callback, func, arg)
		AddPriorityCallback(callback, CallbackPriority.DEFAULT, func, arg)
	end

	-- Register new callbacks
	AddCallback(ModCallbacks.MC_POST_NPC_RENDER, StatusEffectLibrary.OnStatusEffectRender)
	AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, StatusEffectLibrary.OnStatusEffectRender)
	AddCallback(ModCallbacks.MC_PRE_NPC_UPDATE, StatusEffectLibrary.OnStatusEffectUpdate)
	AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, StatusEffectLibrary.OnStatusEffectUpdate)

	--#endregion
end

if StatusEffectLibrary then
	if StatusEffectLibrary.Version > VERSION then
		return
	end

	CACHED_CALLBACKS = StatusEffectLibrary.Callbacks.RegisteredCallbacks
	CACHED_STATUS_FLAGS = StatusEffectLibrary.StatusFlag
	CACHED_STATUS_FLAGS_REVERSE = StatusEffectLibrary.BitflagToStatusFlag
	CACHED_CONFIG = StatusEffectLibrary.StatusConfig
	CACHED_MOD_CALLBACKS = StatusEffectLibrary.AddedCallbacks
end

StatusEffectLibrary = InitMod()
InitFunctions()

if game:GetFrameCount() > 0 then
	for _, ent in ipairs(Isaac.GetRoomEntities()) do
		ent:GetData().StatusEffectLibrary = nil
	end
end
