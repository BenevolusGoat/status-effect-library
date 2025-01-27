---@class ModReference
_G.SELExample = RegisterMod("Status Effect Library Example", 1)
include("src_statuseffectlibrary.status_effect_library")
local SEL = StatusEffectLibrary

local smilyFace = Sprite()
smilyFace:Load("gfx/status_effect_smiley_face.anm2", true)
smilyFace:Play("Idle", true)

SEL.RegisterStatusEffect(
	"SMILY_FACE",
	smilyFace,
	nil,
	nil,
	nil,
	false
)

local function happyTime(_, npc)
	SEL:AddStatusEffect(
		npc,
		SEL.StatusFlag.SMILY_FACE,
		-1,
		EntityRef(npc),
		nil
	)
end

SELExample:AddCallback(ModCallbacks.MC_POST_NPC_INIT, happyTime)
