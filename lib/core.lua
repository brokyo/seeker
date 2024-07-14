local nb = require 'nb/lib/nb'
local musicutil = require("musicutil")
local script_api = {}
local nb_voices = {}

local arp = {
  {
    chord = {},
    direction = 1,
    current_step = 1
  },
  {
    chord = {},
    direction = 1,
    current_step = 1
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
    number = musicutil.generate_scale(60, 'Major'),
    name = {}
}
chord_roots.name = musicutil.note_nums_to_names(chord_roots.number)

function update_chord_roots()
    chord_roots = musicutil.generate_scale(params:get("seeker_root"), params:get("seeker_scale"), 1)
end

local function generate_chord(arp_idx)
  local chord_root = params:get("chord_root_note_" .. arp_idx)
  chord_root = chord_root - 1

  local chord_root_octave = params:get("chord_root_oct_" .. arp_idx)
  chord_root = chord_root + (chord_root_octave * 12)

  local chord_type = params:get("chord_type_" .. arp_idx)
  local chord_inversion = params:get("chord_inversion_" .. arp_idx)

  local new_chord = musicutil.generate_chord(chord_root, chord_type, chord_inversion)

  local octave_range = params:get("octave_range_" .. arp_idx)

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

function script_api:apply_params()
  params:add_separator("seeker-title", "Seeker")

  params:add_group("Tuning", 2)
  params:add_option("seeker_scale", "Scale", scale_names, 1)
  params:add_option("seeker_root", "Root Note", root_note_table, 1)

  for arp_idx = 1, 2 do
    params:add_group("Arpeggiator " .. arp_idx, 24)
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
          (params:get('seeker_root') - 1) + 5 * 12, 
          scale_names[params:get('seeker_scale')]
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

    params:set("duration_mode_" .. arp_idx, 1)
    params:bang()
    _menu.rebuild_params()  
  end
  nb:add_player_params()
end

function arp_handler_1(v)
  if v then
    advance_arp(1)
  elseif not v then
    -- Duration Mode 1 waits for the end of a gate signal
    if params:get("duration_mode_1") == 1 then
      local player = params:lookup_param("seeker_voice_1"):get_player()
      player:note_off(arp[1].chord[arp[1].current_step])
    end
  end
end

function arp_handler_2(v)
  if v then
    advance_arp(2)
  elseif not v then
    -- Duration Mode 1 waits for the end of a gate signal
    if params:get("duration_mode_2") == 1 then
      local player = params:lookup_param("seeker_voice_2"):get_player()
      player:note_off(arp[2].chord[arp[2].current_step])
    end
  end
end

function script_api:setup_crow()
  crow.input[1].change = arp_handler_1
  crow.input[1].mode("change", 1.0, 0.1, "both")
  crow.input[2].change = arp_handler_2
  crow.input[2].mode("change", 1.0, 0.1, "both")
end

return script_api