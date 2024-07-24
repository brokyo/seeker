local nb = require 'nb/lib/nb'
local musicutil = require("musicutil")
local script_api = {}
local nb_voices = {}

local arp = {
  {
    chord = {},
    direction = 1,
    current_step = 1,
    paramquencer_active = false,
    paramquencer_current_pulse = {0, 0, 0, 0},
    paramquencer_current_step = {0, 0, 0, 0} 
  },
  {
    chord = {},
    direction = 1,
    current_step = 1,
    paramquencer_active = false,
    paramquencer_current_pulse = {0, 0, 0, 0},
    paramquencer_current_step = {0, 0, 0, 0} 
  }
}

-- TODO: Some kind of looped random?
local arpeggiator_styles = {"Up", "Down", "Ping Pong", "Random"}

-- Arp Tuning
local root_note_table = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local scale_names = {}
for i = 1, #musicutil.SCALES do
  table.insert(scale_names, musicutil.SCALES[i].name) 
end

local chord_roots = {
    number = musicutil.generate_scale(0, 'Major'),
    name = {}
}
chord_roots.name = musicutil.note_nums_to_names(chord_roots.number)

function update_chord_options()
  -- NB: Subtract one from seeker_key to deal with 0 indexing
  local seeker_key = params:get("seeker_key") - 1
  local seeker_scale = params:string("seeker_scale")
  -- print("New Key: " .. musicutil.note_num_to_name (seeker_key) .. ' ' .. seeker_scale)

  chord_roots.number = musicutil.generate_scale(seeker_key, seeker_scale, 1)
  chord_roots.name = musicutil.note_nums_to_names(chord_roots.number)

  -- tab.print(chord_roots.number)
  -- tab.print(chord_roots.name)

  
  for arp_idx = 1, 2 do
    local chord_root_notes = params:lookup_param('chord_root_note_' .. arp_idx)
    -- Set new in-scale note options
    chord_root_notes.options = chord_roots.name

    -- And reset note to root
    local new_root = chord_roots.name[1]

    params:set('chord_root_note_' .. arp_idx, new_root, 0)

    local new_chord_types = musicutil.chord_types_for_note(new_root, seeker_key, seeker_scale)
    local chord_types = params:lookup_param('chord_type_' .. arp_idx)
    chord_types.options = new_chord_types
    chord_types.count = #new_chord_types
  end
  _menu.rebuild_params()
end

local function generate_chord(arp_idx)
  local chord_root_index = params:get("chord_root_note_" .. arp_idx)
  chord_root_midi = chord_roots.number[chord_root_index]

  local chord_root_octave = params:string("chord_root_oct_" .. arp_idx)
  chord_root_midi = chord_root_midi + (chord_root_octave * 12)

  local chord_type = params:string("chord_type_" .. arp_idx)

  local chord_inversion = params:string("chord_inversion_" .. arp_idx)

  local new_chord = musicutil.generate_chord(chord_root_midi, chord_type, chord_inversion)

  local octave_range = params:string("octave_range_" .. arp_idx)

  local extended_chord = {}
  for i = 1, octave_range do
    for _, note in ipairs(new_chord) do
      table.insert(extended_chord, note + (i * 12))
    end
  end

  new_chord = extended_chord

  arp[arp_idx].chord = new_chord
end

function index_to_velocity(table, index, arp_idx)
  local max_val = params:get("max_velocity_" .. arp_idx)
  local min_val = params:get("min_velocity_" .. arp_idx)
  local mode = params:get("velocity_curve_" .. arp_idx)

  local num_items = #table
  if num_items == 0 then
      return nil, "Table is empty"
  end
  if index < 1 or index > num_items then
      return nil, "Index out of range"
  end

  local normalized = (index - 1) / (num_items - 1)
  local velocity


  if mode == 1 then
    if index % 2 == 0 then
      velocity = min_val
    else
      velocity = max_val
    end
  elseif mode == 2 then
    velocity = min_val + normalized * (max_val - min_val)
  elseif mode == 3 then
    velocity = max_val - normalized * (max_val - min_val)
  elseif mode == 4 then
    velocity = min_val + (math.sin(normalized * math.pi) * (max_val - min_val) / 2) + (max_val - min_val) / 2
  elseif mode == 5 then
    velocity = max_val
  else
      return nil, "Invalid mode"
  end

  return velocity / 100
end

function get_weighted_random_duration(arp_idx)
  local durations = {
    {value = 0.125, chance = params:get("dice_duration_eighth_" .. arp_idx)},
    {value = 0.25, chance = params:get("dice_duration_quarter_" .. arp_idx)},
    {value = 0.5, chance = params:get("dice_duration_half_" .. arp_idx)},
    {value = 1.0, chance = params:get("dice_duration_whole_" .. arp_idx)}
  }

  local total_chance = 0
  for _, duration in ipairs(durations) do
    total_chance = total_chance + duration.chance
  end

  local random_value = math.random() * total_chance
  local cumulative_chance = 0

  for _, duration in ipairs(durations) do
    cumulative_chance = cumulative_chance + duration.chance
    if random_value <= cumulative_chance then
      return duration.value
    end
  end
end

local function advance_arp(idx)
  -- Advance index according to arp rules
  local current_step = arp[idx].current_step
  local chord = arp[idx].chord

  local style = params:get("arp_style_"  .. idx)
  local step_gap = params:get("arp_step_" .. idx)

  -- Select note
  local player = params:lookup_param("seeker_voice_" .. idx):get_player()
  local note = chord[current_step]

  -- Get Velocity
  local velocity = index_to_velocity(chord, current_step, idx)
  -- TODO: This catches an error `attempt to perform arithmetic on a nil value (local 'velocity')` whose root I cannot find
  if not velocity then
    velocity = params:get("max_velocity_" .. idx)
  end

  if params:get("humanize_" .. idx) then
    velocity = velocity * (1 + (math.random() * 0.14 - 0.07))
  end

  local duration_mode = params:get("duration_mode_" .. idx)

  local probability = params:get("probability_" .. idx) / 100

  if math.random() <= probability then
    if duration_mode == 1 then
      -- Play it
      player:note_on(note, velocity)
    elseif duration_mode == 2 then
      local duration = params:get("trigger_duration_" .. idx) / 100
      player:play_note(note, velocity, duration)
    elseif duration_mode == 3 then
      local duration = get_weighted_random_duration(idx)
      player:play_note(note, velocity, duration)
    end
  end

  -- Calculate next step based on style
  local next_step
  if style == 1 then
    next_step = (current_step + step_gap - 1) % #chord + 1
  elseif style == 2 then
    next_step = (current_step - step_gap - 1) % #chord + 1
  elseif style == 3 then
    current_step = current_step + (arp[idx].direction * step_gap)
    if current_step > #chord then
      current_step = #chord - (step_gap - 1)
      arp[idx].direction = -1
    elseif current_step < 1 then
      current_step = 1 + (step_gap - 1)
      arp[idx].direction = 1
    end
    next_step = current_step
  elseif style == 4 then
    next_step = math.random(1, #chord)
  end

  arp[idx].current_step = next_step
end

function script_api:init()
  for i = 1,2 do
    generate_chord(i)
  end
end

function script_api:nb_setup()
    nb:init()
end

function script_api:add_activation_switch()
  params:add_separator("seeker-title", "Seeker")
  params:add_trigger("seeker_crow_focus", "=== K3 to Activate Seeker ===", "momentary", 0)

  params:set_action("seeker_crow_focus", function(param)
    script_api:setup_crow()
    params:hide("seeker_crow_focus")
    _menu.rebuild_params()  
  end)

  -- TODO: Ideally, all of these would be hidden by default. But when I put them in a script they never show up. 
  params:add_group("Tuning", 2)
  params:add_option("seeker_scale", "Scale", scale_names, 1)
  params:set_action("seeker_scale", function(param)
    update_chord_options()
  end)
  params:add_option("seeker_key", "Key", root_note_table, 1)
  params:set_action("seeker_key", function(param)
    update_chord_options()
  end)
 
  for arp_idx = 1, 2 do
    -- Arpeggiator Params
    params:add_group("Arpeggiator " .. arp_idx, 64)
    -- Style Params
    params:add_separator("arp_style_header" .. arp_idx, "Style")
    nb:add_param("seeker_voice_" .. arp_idx, "NB Voice")
    params:add_option("arp_style_" .. arp_idx, "Style", arpeggiator_styles, 1)
    params:add_number("arp_step_" .. arp_idx, "Step", 1, 4, 1)

    -- Chord Params
    params:add_separator("arp_chord_header" .. arp_idx, "Chord")
    params:add_option("chord_root_note_" .. arp_idx, "Chord Root Note", chord_roots.name, 1)
    params:set_action('chord_root_note_' .. arp_idx, function(param)
      generate_chord(arp_idx)
    end)
    params:add_number("chord_root_oct_" .. arp_idx, "Chord Root Octave", 1, 8, 4)
    params:set_action('chord_root_oct_' .. arp_idx, function(param)
      generate_chord(arp_idx)
    end)
    params:add_option("chord_type_" .. arp_idx, "Chord Type",
      musicutil.chord_types_for_note(
          chord_roots.number[params:get('chord_root_note_' .. arp_idx)],
          params:get('seeker_key') - 1, 
          params:string('seeker_scale')
      ))
    params:set_action('chord_type_' .. arp_idx, function(param)
      generate_chord(arp_idx)
      end)
    params:add_number("chord_inversion_" .. arp_idx, "Inversions", 0, 3, 0)
    params:set_action('chord_inversion_' .. arp_idx, function(param)
      generate_chord(arp_idx)
    end)
    params:add_number("octave_range_" .. arp_idx, "Octave Range", 1, 4, 1)
    params:set_action('octave_range_' .. arp_idx, function(param)
      generate_chord(arp_idx)
    end)

    -- Expresion Params
    params:add_separator("arp_expression_header" .. arp_idx, "Expression")
    params:add_control("probability_" .. arp_idx, "Probability", controlspec.new(0, 100, 'lin', 1, 100, '%'))
    params:add_option("velocity_curve_" .. arp_idx, "Velocity Curve", {"Alternate", "Ramp Up", "Ramp Down", "Sin", "Flat"}, 1)
    params:add_number("max_velocity_" .. arp_idx, "Velocity Max", 1, 100, 70)
    params:add_number("min_velocity_" .. arp_idx, "Velocity Mix", 1, 100, 40)
    params:add_option("humanize_" .. arp_idx, "Humanize", {"Off", "On"}, 1)

    -- Rhythm Params
    params:add_separator("arp_rhythm_header" .. arp_idx, "Rhytm")
    params:add_option("duration_mode_" .. arp_idx, "Duration Control", {"Gate Length", "Trigger", "Dice"}, 1)
    params:set_action('duration_mode_' .. arp_idx, function(param)
      if param == 1 then
        params:hide("trigger_duration_" .. arp_idx)
        params:hide("dice_duration_eighth_" .. arp_idx)
        params:hide("dice_duration_quarter_" .. arp_idx)
        params:hide("dice_duration_half_" .. arp_idx)
        params:hide("dice_duration_whole_" .. arp_idx)
      elseif param == 2 then
        params:show("trigger_duration_" .. arp_idx)
        params:hide("dice_duration_eighth_" .. arp_idx)
        params:hide("dice_duration_quarter_" .. arp_idx)
        params:hide("dice_duration_half_" .. arp_idx)
        params:hide("dice_duration_whole_" .. arp_idx)
      elseif param == 3 then
        params:hide("trigger_duration_" .. arp_idx)
        params:show("dice_duration_eighth_" .. arp_idx)
        params:show("dice_duration_quarter_" .. arp_idx)
        params:show("dice_duration_half_" .. arp_idx)
        params:show("dice_duration_whole_" .. arp_idx)
      end

      _menu.rebuild_params()
    end)
    params:add_number("trigger_duration_" .. arp_idx, "Play Duration", 0, 100, 50)
    params:add_number("dice_duration_eighth_" .. arp_idx, "1/8 Note Chance", 0, 10, 5)
    params:add_number("dice_duration_quarter_" .. arp_idx, "1/4 Note Chance", 0, 10, 5)
    params:add_number("dice_duration_half_" .. arp_idx, "1/2 Note Chance", 0, 10, 5)
    params:add_number("dice_duration_whole_" .. arp_idx, "Whole Note Chance", 0, 10, 5)    

    params:add_separator("paramquencer_" .. arp_idx, "Paramquencer [Alpha]")
    params:add_binary("paramquencer_toggle_" .. arp_idx, "Enable Paramquencer", "toggle", 0)

    -- TODO: This is brittle hack to be addressed when I'm back from vacation.
    -- We're duplicating the param list in order to deal with dynamic IDs.
    -- SEE:get_sequenced_params()
    local available_params = {
      'seeker_voice_' .. arp_idx,
      'arp_style_' .. arp_idx, 
      'arp_step_' .. arp_idx, 
      'chord_root_note_' .. arp_idx, 
      'chord_root_oct_' .. arp_idx, 
      'chord_type_' .. arp_idx, 
      'chord_inversion_' .. arp_idx, 
      'octave_range_' .. arp_idx 
    }
    -- 37 + 1 + 24

    -- Create the four Paramquencer lanes
    params:add_binary("sync_paramquencer_" .. arp_idx, "Sync Paramquencer Lanes", "momentary")
    params:set_action("sync_paramquencer_" .. arp_idx, function(state)
      if state == 1 then
        sync_paramquencer(arp_idx)
      end
    end)
    params:add_number("sequencer_lane_arp_" .. arp_idx, "Lane", 1, 4, 1)

    for lane_idx = 1, 4 do
      params:add_number("pulses_per_step_lane_" .. lane_idx .. "_arp_" .. arp_idx, "Pulses Per Step", 1, 64, 12)
      params:add_option("sequenced_param_lane_" .. lane_idx .. "_arp_" .. arp_idx, "Param", available_params, 1)
      params:add_number("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx, "Step Count", 1, 6, 0)
      
      for step_idx = 1, 6 do
        params:add_number("step_" .. step_idx .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx, "Step " .. step_idx, 1, 36, 1)
      end

      params:set_action("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx, function(step_length)
        for step_idx = 1, 6 do
          if step_idx <= step_length then
            params:show("step_" .. step_idx .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          else
            params:hide("step_" .. step_idx .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          end
        end
        _menu.rebuild_params()
      end)
    end

    params:set_action("sequencer_lane_arp_" .. arp_idx, function(selected_lane)
      for lane_idx = 1, 4 do
        if lane_idx == selected_lane then
          params:show("pulses_per_step_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          params:show("sequenced_param_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          params:show("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx)

          for step_idx = 1, params:get("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx) do
            params:show("step_" .. step_idx .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          end

        else
          params:hide("pulses_per_step_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          params:hide("sequenced_param_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          params:hide("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          for step_idx = 1, 6 do
            params:hide("step_" .. step_idx .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx)
          end
        end
      end
      _menu.rebuild_params()
    end)


    params:set_action("paramquencer_toggle_" .. arp_idx, function(active)
      arp[arp_idx].paramquencer_active = true
      params:show("sync_paramquencer_" .. arp_idx)
      local default_lane = params:get("sequencer_lane_arp_" .. arp_idx)
      params:show("sequencer_lane_arp_" .. arp_idx)
      params:show("pulses_per_step_lane_" .. default_lane .. "_arp_" .. arp_idx)
      params:show("sequenced_param_lane_" .. default_lane .. "_arp_" .. arp_idx)
      params:show("step_count_lane_" .. default_lane .. "_arp_" .. arp_idx)

      for step_idx = 1, params:get("step_count_lane_" .. default_lane .. "_arp_" .. arp_idx) do
        params:show("step_" .. step_idx .. "_lane_" .. default_lane .. "_arp_" .. arp_idx)
      end

      params:hide("paramquencer_toggle_" .. arp_idx)
      _menu.rebuild_params()
    end)

    end

  for arp_idx = 1, 2 do    
    params:hide("sync_paramquencer_" .. arp_idx)
    params:hide("sequencer_lane_arp_" .. arp_idx)
    for lane_idx = 1, 4 do
      params:hide("pulses_per_step_lane_" .. lane_idx .. "_arp_" .. arp_idx)
      params:hide("sequenced_param_lane_" .. lane_idx .. "_arp_" .. arp_idx)
      params:hide("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx)
      for step_idx = 1, 6 do
        params:hide("step_" .. step_idx .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx)
      end
    end
 
  end
  _menu.rebuild_params()

  nb:add_player_params()
end

function arp_handler_1(rise)
  -- Advance the arp
  if rise then
    advance_arp(1)
    -- If paramquencer is active, iterate the pulse count
    if arp[1].paramquencer_active then
      increment_paramquencer_step(1)
    end
  -- If we're set to the gate length duration mode, close the voice when the fall comes in
  elseif not rise then
    if params:get("duration_mode_1") == 1 then
      local player = params:lookup_param("seeker_voice_1"):get_player()
      player:note_off(arp[1].chord[arp[1].current_step])
    end
  end
end

function arp_handler_2(rise)
  -- Advance the arp
  if rise then
    advance_arp(2)
    -- If paramquencer is active, iterate the pulse count
    if arp[2].paramquencer_active then
      increment_paramquencer_step(2)
    end
  -- If we're set to the gate length duration mode, close the voice when the fall comes in
  elseif not rise then
    if params:get("duration_mode_2") == 1 then
      local player = params:lookup_param("seeker_voice_2"):get_player()
      player:note_off(arp[2].chord[arp[2].current_step])
    end
  end
end

function get_sequenced_param(arp_idx)

  local selected_param_index = params:get('sequenced_param_' .. arp_idx)

    -- Identify all the params that can be sequenced
  local available_params = {
    'seeker_voice_' .. arp_idx,
    'arp_style_' .. arp_idx, 
    'arp_step_' .. arp_idx, 
    'chord_root_note_' .. arp_idx, 
    'chord_root_oct_' .. arp_idx, 
    'chord_type_' .. arp_idx, 
    'chord_inversion_' .. arp_idx, 
    'octave_range_' .. arp_idx 
  }

  return available_params[selected_param_index]
end

function increment_paramquencer_step(arp_idx)
  for lane_idx = 1, 4 do
    local step_count = params:get("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx)
    if step_count == 0 then
      return
    end

    
    local pulses_per_step = params:get("pulses_per_step_lane_" .. lane_idx .. "_arp_" .. arp_idx)
    
    arp[arp_idx].paramquencer_current_pulse[lane_idx] = (arp[arp_idx].paramquencer_current_pulse[lane_idx] % pulses_per_step + 1)

    if arp[arp_idx].paramquencer_current_pulse[lane_idx] == 1 and params:get("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx) > 0 then
      arp[arp_idx].paramquencer_current_step[lane_idx] = (arp[arp_idx].paramquencer_current_step[lane_idx] % params:get("step_count_lane_" .. lane_idx .. "_arp_" .. arp_idx)) + 1

      local next_step_value = params:get("step_" .. arp[arp_idx].paramquencer_current_step[lane_idx] .. "_lane_" .. lane_idx .. "_arp_" .. arp_idx)
      local param_to_update = params:string("sequenced_param_lane_" .. lane_idx .. "_arp_" .. arp_idx)

      print("Change Param: " .. param_to_update .. " Value: " .. next_step_value)
      params:set(param_to_update, next_step_value)
      _menu.rebuild_params()
    end
  end
end

function sync_paramquencer(arp_idx)
  for lane_idx = 1, 4 do
    arp[arp_idx].paramquencer_current_pulse[lane_idx] = 0
    arp[arp_idx].paramquencer_current_step[lane_idx] = 0
  end
  print("Paramquencer for arp " .. arp_idx .. " synced.")
end

function script_api:setup_crow()
  print("Seeker: Crow Listening")
  crow.input[1].change = arp_handler_1
  crow.input[1].mode("change", 1.0, 0.1, "both")

  crow.input[2].change = arp_handler_2
  crow.input[2].mode("change", 1.0, 0.1, "both")
end

return script_api