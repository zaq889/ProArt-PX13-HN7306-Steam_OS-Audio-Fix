-- ProArt PX13 (HN7306) headphone jack auto-switch.
-- The speaker path is a mono virtual sink (kernel mirror-mode workaround) and is
-- the default when nothing is plugged in. When the headphone jack route becomes
-- available, prefer the real stereo headphone sink; fall back to mono otherwise.
log = Log.open_topic ("s-px13-jack")

local HEADPHONE_NODE = "alsa_output.pci-0000_c4_00.5-platform-amd_sdw.HiFi__Headphones__sink"
local MONO_NODE = "px13_speaker_mono"

SimpleEventHook {
  name = "px13-jack/default-node",
  after = { "default-nodes/find-selected-default-node",
            "default-nodes/find-stored-default-node" },
  before = { "default-nodes/find-best-default-node" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-default-node" },
    },
  },
  execute = function (event)
    local props = event:get_properties ()
    if props["default-node.type"] ~= "audio.sink" then
      return
    end

    local available_nodes = event:get_data ("available-nodes")
    available_nodes = available_nodes and available_nodes:parse ()
    if not available_nodes then
      return
    end

    local has_headphone = false
    local has_mono = false
    for _, node_props in ipairs (available_nodes) do
      local name = node_props["node.name"]
      if name == HEADPHONE_NODE then has_headphone = true end
      if name == MONO_NODE then has_mono = true end
    end

    if has_headphone then
      log:info ("headphones active - selecting headphone sink")
      event:set_data ("selected-node", HEADPHONE_NODE)
      event:set_data ("selected-node-priority", 40000)
      event:set_data ("selected-route-priority", 0)
    elseif has_mono then
      log:info ("no headphones - selecting mono speaker sink")
      event:set_data ("selected-node", MONO_NODE)
      event:set_data ("selected-node-priority", 35000)
      event:set_data ("selected-route-priority", 0)
    end
  end
}:register ()