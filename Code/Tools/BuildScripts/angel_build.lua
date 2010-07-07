------------------------------------------------------------------------------
-- Copyright (C) 2008-2010, Shane J. M. Liesegang
-- All rights reserved.
-- 
-- Redistribution and use in source and binary forms, with or without 
-- modification, are permitted provided that the following conditions are met:
-- 
--     * Redistributions of source code must retain the above copyright 
--       notice, this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above copyright 
--       notice, this list of conditions and the following disclaimer in the 
--       documentation and/or other materials provided with the distribution.
--     * Neither the name of the copyright holder nor the names of any 
--       contributors may be used to endorse or promote products derived from 
--       this software without specific prior written permission.
-- 
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
-- ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
-- POSSIBILITY OF SUCH DAMAGE.
------------------------------------------------------------------------------

require "lfs"
require "ex"
require "io"

if (package.path == nil) then
  package.path = ""
end
local mydir = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]]
if (mydir == nil) then
  mydir = "."
end
package.path = mydir .. "?.lua;" .. package.path
package.path = package.path .. ";" .. mydir .. "lua-lib/penlight-0.8/lua/?/init.lua"
package.path = package.path .. ";" .. mydir .. "lua-lib/penlight-0.8/lua/?.lua"

require "pl.path"
require "pl.dir"

-- whether this file is hidden and should thus be ignored
--  (mostly used for skipping .svn directories)
function _isdotfile(path)
  if (pl.path.basename(path):sub(1,1) == ".") then
    return true
  else
    return false
  end
end

-- because the penlight copy function doesn't preserve case on windows. :-(
function copyfile(from, to)
  if (pl.path.is_windows) then
    os.execute(string.format('copy /Y "%s" "%s" > nul', from, to))
  else
    pl.dir.copyfile(from, to, true)
  end
end

-- this and makedirs blatantly copied from penlight, but without
--  normalizing the case on Windows, because that is dumb
local dirpat
if pl.path.is_windows then
    dirpat = '(.+)\\[^\\]+$'
else
    dirpat = '(.+)/[^/]+$'
end

-- makes a path recursively
--  (there was some good reason at some point to re-implement this here instead
--  of using the penlight version)
function makedirs(p)
  -- windows root drive case
  if(p:find('^%a:$')) then
    return true
  end

  if not pl.path.isdir(p) then
    local subp = p:match(dirpat)
    if not (makedirs(subp)) then
      io.stderr:write("ERROR: Cannot create " .. subp .. "\n")
      os.exit(1)
    end
    return lfs.mkdir(p)
  else
    return true
  end
end

-- recursively copy a directory and its files from src to dst
function recursive_copy(src, dst)
  if (_isdotfile(src)) then
    -- print("Skipping " .. pl.path.basename(src))
    return
  end
  
  if (not pl.path.exists(dst)) then
    makedirs(dst)
  end
  
  local names = pl.dir.getfiles(src, "")
  for _, name in pairs(names) do
    if (not _isdotfile(name)) then
      name = pl.path.basename(name)
      local srcname = pl.path.join(src, name)
      local dstname = pl.path.join(dst, name)
      copyfile(srcname, dstname)
    end
  end
  
  local dirs = pl.dir.getdirectories(src, "")
  for _, dirname in pairs(dirs) do
    dirname = pl.path.basename(dirname)
    local srcname = pl.path.join(src, dirname)
    local dstname = pl.path.join(dst, dirname)
    recursive_copy(srcname, dstname)
  end
end

-- split a string into a table along separators
function string:split(sep)
  local sep, fields = sep or " ", {}
  local pattern = string.format("([^%s]+)", sep)
  self:gsub(pattern, function(c) fields[#fields+1] = c end)
  return fields
end

-- <sigh> the penlight library only joins paths one at a time. :-(
function fulljoin(...)
  local for_return = ""
  for i, v in ipairs(arg) do
    for_return = pl.path.join(for_return, v)
  end
  return for_return
end

-- load a file using the passed table as its environment
function loadFileIn(filename, environment)
  local f, err = loadfile(filename)
  if (f == nil) then
   print(err)
  end
  if (environment == nil) then
   environment = getfenv()
  end
  setfenv(f, environment)
  return f()
end

-- get the absolute path toe the current file
function get_file_location()
  local file_location = debug.getinfo(2,'S').source
  if (file_location:sub(1,1) == "@") then
    file_location = file_location:sub(2, -1)
  end
  return (pl.path.dirname(pl.path.abspath(file_location)))
end

-- find a local install of SWIG
function get_swig_path()
  if (pl.path.is_windows) then
    -- we're on windows, use the distributed swig
    return fulljoin(pl.path.dirname(get_file_location()), "..", "swigwin-1.3.36", "swig.exe")
  end
  
  local ports_path = "/opt/local/bin/swig"
  if (pl.path.exists(ports_path)) then
    -- this mac user has wisely installed swig from macports
    return ports_path
  end
    
  -- check for other installed swig
  local f = assert(io.popen("which swig", 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if (s == "") then
    io.stderr:write("ERROR: swig not found.\n")
    os.exit(1)
  end
  return s:gsub("\n" , "")
end

-- generate typemap inheritance for SWIG factories
function generate_typemaps(interface_directory, additional_define)
  local swig = get_swig_path()
  local junkfile = fulljoin(interface_directory, "..", "..", "..", "Tools", "BuildScripts", "build_cache", "swigout.txt")
  local inheritance_file = ""
  if (additional_define == "INTROGAME") then
    inheritance_file = pl.path.join(interface_directory, "inheritance_intro.i")
  else
    inheritance_file = pl.path.join(interface_directory, "inheritance.i")
  end
  if (not pl.path.exists(inheritance_file)) then
    -- need to make sure we have at least a blank file for swig to include 
    --  when it runs to get the type data
    local inheritance_handle = assert(io.open(inheritance_file, "w"))
    inheritance_handle:close()
  end
  local swig_options = ""
  if (additional_define ~= nil) then
    swig_options = swig_options .. " -D" .. additional_define
  end
  swig_options = swig_options .. " -c++ -lua -Werror -debug-typedef -I" .. interface_directory .. " -o " .. junkfile .. " " .. pl.path.join(interface_directory, "angel.i")
  local f = assert(io.popen(swig .. swig_options, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  
  local separator = "-------------------------------------------------------------"
  local class_data = {}
  local immediate_class_data = {}
  local class_pattern = "Type scope '(%w+)'"
  local inh_patterh = "Inherits from '(%w+)'"
  local splits = s:split(separator)
  for _, v in pairs(splits) do
    local _, _, class = v:find(class_pattern)
    if (class ~= nil) then
      local lines = v:split("\n")
      if (#lines == 1) then
        -- no inheritance here
      else
        immediate_class_data[class] = {}
        for i=1,#lines do -- skip the first line
          local _, _, base = lines[i]:find(inh_patterh)
          if (base ~= nil) then
            if (class_data[base] == nil) then
              class_data[base] = {}
            end
            table.insert(class_data[base], class)
            table.insert(immediate_class_data[class], base)
          end
        end
      end
    end
  end
    
  local sortf = function(class1, class2)
    local parents1 = immediate_class_data[class1]
    local parents2 = immediate_class_data[class2]
    if (parents1 == nil and parents2 == nil) then
      return false
    end
    if (parents1 ~= nil) then
      for _, p in pairs(parents1) do
        if (p == class2) then
          -- the second class is a parent of the first
          return true
        end
      end
    end
    return false
  end
  
  local out_strings = {}
  for base, descendants in pairs(class_data) do
    table.sort(class_data[base], sortf)
    table.insert(out_strings, "%factory("..base.."*, "..table.concat(descendants, ", ")..");")
  end
  
  local out_string = "%include <factory.i>\n\n" .. table.concat(out_strings, "\n")
  
  local out_file = io.open(inheritance_file, "r")
  local current_file = out_file:read("*a")
  out_file:close()
  if (current_file ~= out_string) then
    out_file = io.open(inheritance_file, "w")
    out_file:write(out_string)
    out_file:close()
  end
end

