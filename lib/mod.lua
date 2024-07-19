local mod = require 'core/mods'
local script_core = {}

mod.hook.register("script_pre_init", "a new mod", function()
    script_core = include('seeker/lib/core')  
    script_core:nb_setup()
    script_core:add_activation_switch()
    script_core:init()
end)