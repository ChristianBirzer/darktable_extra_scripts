--[[
    This file is part of darktable,
    copyright (c) 2022 Christian Birzer

    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    darktable is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
ExportToPublish


WARNING
This script was only tested on Windows

]]

local dt = require 'darktable'
local du = require "lib/dtutils"
local df = require 'lib/dtutils.file'
local dsys = require 'lib/dtutils.system'

local mod = "ExportToPublish"

du.check_min_api_version("7.0.0", mod)

local script_data = {}

-- namespace
local module = {}
module.module_installed = false
module.event_registered = false
module.widgets = {}

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again

local act_os = dt.configuration.running_os
local os_path_seperator = '/'
if dt.configuration.running_os == 'windows' then os_path_seperator = '\\' end

-- find locale directory:
local scriptfile = debug.getinfo( 1, "S" )
local localedir = dt.configuration.config_dir.."/lua/locale/"
if scriptfile ~= nil and scriptfile.source ~= nil then
  local path = scriptfile.source:match( "[^@].*[/\\]" )
  localedir = path..os_path_seperator.."locale"
end
dt.print_log( "localedir: "..localedir )

-- Tell gettext where to find the .mo file translating messages for a particular domain
local gettext = dt.gettext
gettext.bindtextdomain( mod, localedir )

local function _(msgid)
    return gettext.dgettext( mod, msgid )
end

--Format strings for the commands to open the corresponding OS's file manager.
local open_dir = {}
open_dir.windows = "explorer.exe /n, %s"
open_dir.macos = "open %s"
open_dir.linux = [[busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1 ShowFolders ass 1 %s ""]]

local open_files = {}
open_files.windows = "explorer.exe /select,%s"
open_files.macos = "open -Rn %s"
open_files.linux = [[busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1 ShowItems ass %d %s ""]]

local gui = {
  section_presets = {},
  combo_presets = {},
  box_preset_buttons = {},
  button_preset_update = {},
  button_preset_delete = {},
  box_preset_create = {},
  entry_preset_name = {},
  button_preset_create = {},
  section_publish = {},
  label_target_path = {},
  filechooser_target_path = {},
  check_overwrite = {},
  label_tag = {},
  entry_tag = {},
  check_open_path = {},
}

local presets = {} -- table with all presets


local function split( text, separator )
  local result = {}
  local len = text:len()
  len = text:len()
  if len < 2 then
    return result
  end
  local start = 1
  local escape = false
  for i=2,len do
    local doescape = false
    local thischar = text:sub( i, i )
    if( not escape and '\\' == thischar ) then
      doescape = true
    end
    if( not escape ) then
      if( thischar == separator ) then
        local match = text:sub( start, i - 1)
        table.insert(result, match )
        start = i + 1
      end
    end
    escape = doescape
  end

  if start < len then
     table.insert( result, text:sub( start, len ) )
  end

  return result
end

local function escape( text )
  local result = text:gsub("\\", "\\\\" )
  result = result:gsub(";", "\\;" )
  result = result:gsub("|", "\\|" )

  print( "escaping '" .. text .. "' to '" .. result .. "'" )
  return result
end

local function unescape( text )
  local result = text:gsub( "\\\\", "\\" )
  result = result:gsub( "\\;", ";" )
  result = result:gsub( "\\|", "|" )
  print( "unescaping '" .. text .. "' to '" .. result .. "'" )
  return result
end

local function dump_presets()
  print( "----- presets -------" )
  for _, preset in ipairs( presets ) do
    for key, value in pairs( preset ) do
      print ( "  > " .. key .. " : " .. value )
    end
    print( "" )
  end
end

local function update_preset_combo( select_preset )
  -- clear combobox:
  while #gui.combo_presets > 0 do
    gui.combo_presets[ 1 ] = nil
  end
  local entry_to_select = 0
  for i, preset in ipairs( presets ) do
    local preset_name = preset[ 'n' ]
    print( "adding preset " .. preset_name )
    gui.combo_presets[ #gui.combo_presets + 1 ] = preset_name
    if preset_name == select_preset then
      entry_to_select = i
    end
  end
  gui.combo_presets.selected = entry_to_select
end

local function store_presets()
  local preset_string = ""
  for _, preset in ipairs( presets ) do
    print( "preset:" )
    for key, value in pairs( preset ) do
      preset_string = preset_string .. key .. "=" .. escape( value ) .. ";"
    end
    preset_string = preset_string .. "|"
  end
  print( "resulting preset string:" )
  print( preset_string )
  dt.preferences.write( mod, "presets", "string", preset_string )
end

local function load_presets()
  local preset_string = dt.preferences.read( mod, "presets", "string")
  local new_presets = {}
  local new_preset_strings = {}
  new_preset_strings = split( preset_string, '|' )
  print( "loaded preset string: " .. preset_string )

  for i, preset in ipairs( new_preset_strings ) do
    print( i .. ": " .. preset )
    local new_preset = {}
    local new_single_preset = split( preset, ';' )
    for j, keyvalue in ipairs( new_single_preset ) do
      local key, value = keyvalue:match( "^(.)=(.*)" )
      if value == nil then
        value = ""
      end
      if key ~= nil then
        print( "  > " .. j .. ": " .. keyvalue .. " key=" .. key .. "  value=" .. unescape( value ) )
        new_preset[ key ] = unescape( value )
      end
    end
    table.insert( new_presets, new_preset )
  end
  presets = new_presets
  dump_presets()
end

local function preset_exists( preset_name )
  for _, preset in ipairs( presets ) do
    if preset[ 'n' ] == preset_name then
      return true
    end
  end
  return false
end

local function preset_restore( combobox )
  print( "restore preset " .. combobox.selected )

  if( combobox.selected > 0 ) then
    local preset = presets[ combobox.selected ]

    gui.entry_preset_name.text        = preset[ 'n' ]
    gui.filechooser_target_path.value = preset[ 'p' ]
    gui.entry_tag.text                = preset[ 't' ]
    gui.check_open_path.value         = preset[ 'o' ] == 'true'
    gui.check_overwrite.value         = preset[ 'v' ] == 'true'
    dt.preferences.write( mod, "active_preset", "string", preset[ 'n' ] )
  end
end

local function preset_delete()
  print( "delete preset " .. gui.combo_presets.selected )

  if( gui.combo_presets.selected > 0 ) then
    table.remove( presets, gui.combo_presets.selected )
  end
  store_presets()
  update_preset_combo( nil )
end

local function preset_create()
  local preset_name = gui.entry_preset_name.text
  if preset_exists( preset_name ) then
    dt.print( _("A preset with this name already exists. Please use an other name or delete the old preset first" ) )
    return
  end
  local preset_path = gui.filechooser_target_path.value
  local preset_opendir = "false"
  local preset_tags = gui.entry_tag.text
  if gui.check_open_path.value == true then
    preset_opendir = "true"
  end
  local preset_overwrite = "false"
  if gui.check_overwrite.value == true then
    preset_overwrite = "true"
  end
  print( "create preset " .. preset_name )

  local preset = {}
  preset[ 'n' ] = preset_name
  preset[ 'p' ] = preset_path
  preset[ 'o' ] = preset_opendir
  preset[ 'v' ] = preset_overwrite
  preset[ 't' ] = preset_tags
  table.insert( presets, preset )

  store_presets()
  update_preset_combo( preset_name )
end

local function preset_update()
  print( "update preset " .. gui.combo_presets.selected )
  preset_delete()
  preset_create()
end

local function set_target_directory()
  print( "set_target_directory:" )
  local new_path = gui.filechooser_target_path.value
  print( "target directory is " ..  new_path )
  gui.filechooser_target_path.tooltip =  new_path
end

gui.section_presets = dt.new_widget( "section_label" ) {
  label = _( "presets" )
}

gui.combo_presets = dt.new_widget( "combobox" ) {
  label = _( "preset" ),
  tooltip = _( "select the preset to restore" ),
  changed_callback = preset_restore
}

gui.button_preset_update = dt.new_widget( "button" ) {
  label = _( "update" ),
  tooltip = _( "update the selected preset with the current settings" ),
  clicked_callback = preset_update
}

gui.button_preset_delete = dt.new_widget( "button" ) {
  label = _( "delete" ),
  tooltip = _( "delete the selected preset" ),
  clicked_callback = preset_delete
}

gui.box_preset_buttons = dt.new_widget( "box" ) {
  orientation = "horizontal",
  gui.button_preset_update,
  gui.button_preset_delete
}

gui.entry_preset_name = dt.new_widget( "entry" ) {
  placeholder = _( "preset name" ),
  tooltip = _( "enter a name for a new preset" ),
  text = "",
  editable = true
}

gui.button_preset_create = dt.new_widget( "button" ) {
  label = _( "create" ),
  tooltip = _( "create a new preset" ),
  clicked_callback = preset_create
}

gui.box_preset_create = dt.new_widget( "box" ) {
  orientation = "horizontal",
  gui.entry_preset_name,
  gui.button_preset_create
}

gui.section_publish = dt.new_widget( "section_label" ) {
  label = _( "publish target" )
}

gui.label_target_path = dt.new_widget( "label" ) {
  label = _( "target path" ),
}

gui.filechooser_target_path = dt.new_widget( "file_chooser_button" ) {
  title = _( "browse" ),
  tooltip = _( "browse for the target directory" ),
  is_directory = true,
  changed_callback = set_target_directory
}

gui.check_overwrite = dt.new_widget("check_button"){
  label = _( "overwrite export file"),
  value = false,
  tooltip = _("overwrite exported file if it already exists in target path"),
  reset_callback = function ( self )
    self.value = false
  end

}

gui.label_tag = dt.new_widget( "label" ) {
  label = _( "tags" ),
}

gui.entry_tag = dt.new_widget( "entry" ) {
  tooltip = _( "tags to add after export, multiple tags separated by comma" ),
  text = "",
  placeholder = "tags",
  editable = true
}

gui.check_open_path = dt.new_widget( "check_button" ) {
  label = _( "open directory after export" ),
  value = false,
  tooltip = _( "open target directory in file manager after export" ),
  reset_callback = function( self )
    self.value = false
  end
}

local gui_widgets = dt.new_widget( "box" ) {
  orientation = "vertical",
  gui.section_presets,
  gui.combo_presets,
  gui.box_preset_buttons,
  gui.box_preset_create,
  gui.section_publish,
  gui.label_target_path,
  gui.filechooser_target_path,
  gui.label_tag,
  gui.entry_tag,
  gui.check_overwrite,
  gui.check_open_path,
}

local function destroy()
  dt.destroy_storage( mod )
end

local function store(
    storage,
    image,
    format,
    filename,
    number,
    total,
    high_quality, -- : boolean,
    extra_data    -- : table
  )
  print( "store: format.name=" .. format.name .. " size: " .. format.max_width .. " * " .. format.max_height )
end

--removes spaces from the front and back of passed in text
local function clean_spaces(text)
  text = string.gsub(text,"^%s*","")
  text = string.gsub(text,"%s*$","")
  return text
end

local function addTags( image )
  local setTag = gui.entry_tag.text
  if setTag ~= nil then -- add additional user-specified tags
    for tag in string.gmatch(setTag, "[^,]+") do
      tag = clean_spaces(tag)
      tag = dt.tags.create(tag)
      dt.tags.attach(tag, image)
    end
  end
end

local function openFileManager( path, openSingleFile )
  local runCmd
  if openSingleFile then
    run_cmd = string.format( open_files[ act_os ], df.sanitize_filename( path ) )
  else
    run_cmd = string.format( open_dir[ act_os ], df.sanitize_filename( "file://" .. path ) )
  end
  dt.print_log( mod .. " run_cmd = "..run_cmd)
  dsys.external_command(run_cmd)
end


-- export images, add tags and open target folder
local function finalize( storage, image_table, extra_data )
  print( "exported images: " )

  local targetPath = gui.filechooser_target_path.value
  local targetFileName = ""
  local imageCount = 0

  -- move exported image to target path
  -- create unique filename or overwrite if requested
  local result
  for image, exportedImage in pairs(image_table) do
    targetFileName = targetPath .. os_path_seperator .. df.get_filename( exportedImage )
    if gui.check_overwrite.value == true then
      if df.check_if_file_exists( targetFileName ) then
        result = os.remove(targetFileName)
      end
      result = df.file_move( exportedImage, targetFileName )
    else
      local loop = 1
      while df.check_if_file_exists( targetFileName ) do
        targetFileName = df.filename_increment( targetFileName )
        loop = loop + 1
        if loop > 99 then -- safety to avoid endless increments
          break
        end
      end
      result = df.file_move( exportedImage, targetFileName )
    end
    print( "exported image: " )
    print( "image: " .. image.path .. " / " .. image.filename .. "  export: " .. exportedImage )

    if not result then
      dt.print( _( "error moving image to target folder" ) )
    else
      print( "moved image to " .. targetFileName )
      addTags( image )
      imageCount = imageCount + 1
    end
  end

  if imageCount == 1 then
    -- open file manager for particular image
    print( "open explorer for image " .. targetFileName )
    openFileManager( targetFileName, true )
  else
    -- open file manager for directory
    openFileManager( targetPath, false )
    print( "open explorer for directory " .. targetPath )
  end

end

local function initialize( storage, format, images, high_quality, extra_data )
  print( "image: " ..  format.max_width .. " * " .. format.max_height .. " plugin name: " .. format.plugin_name .. " name: " .. format.name .. " ext: " .. format.extension )
  format.max_width = 100
  format.max_height = 100
  print( "exporting images " )
  return nil
end

local function show()
end

-- register new storage -------------------------------------------------------
local function register()
  dt.register_storage( mod, _( "export to publish" ), store, finalize, nil, initialize, gui_widgets )
end

local function restart()
  register()
  show()
end

register()

load_presets()
local active_preset = dt.preferences.read( mod, "active_preset", "string" )
update_preset_combo( active_preset )

script_data.destroy = destroy
script_data.restart = restart
script_data.destroy_method = "hide"
script_data.show = show

return script_data
