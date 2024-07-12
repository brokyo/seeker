local mod = require 'core/mods'
local script_core = {}

mod.hook.register("script_post_init", "a new mod", function()
    script_core = include('seeker/lib/core')  
    script_core:nb_setup()
    script_core:apply_params()
    script_core:setup_crow()
    script_core:init()
end)