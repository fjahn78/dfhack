-- Common startup file for all dfhack plugins with lua support
-- The global dfhack table is already created by C++ init code.

-- Console color constants

COLOR_RESET = -1
COLOR_BLACK = 0
COLOR_BLUE = 1
COLOR_GREEN = 2
COLOR_CYAN = 3
COLOR_RED = 4
COLOR_MAGENTA = 5
COLOR_BROWN = 6
COLOR_GREY = 7
COLOR_DARKGREY = 8
COLOR_LIGHTBLUE = 9
COLOR_LIGHTGREEN = 10
COLOR_LIGHTCYAN = 11
COLOR_LIGHTRED = 12
COLOR_LIGHTMAGENTA = 13
COLOR_YELLOW = 14
COLOR_WHITE = 15

-- Events

if dfhack.is_core_context then
    SC_WORLD_LOADED = 0
    SC_WORLD_UNLOADED = 1
    SC_MAP_LOADED = 2
    SC_MAP_UNLOADED = 3
    SC_VIEWSCREEN_CHANGED = 4
    SC_CORE_INITIALIZED = 5
end

-- Error handling

safecall = dfhack.safecall

function dfhack.pcall(f, ...)
    return xpcall(f, dfhack.onerror, ...)
end

function dfhack.with_finalize(...)
    return dfhack.call_with_finalizer(0,true,...)
end
function dfhack.with_onerror(...)
    return dfhack.call_with_finalizer(0,false,...)
end

local function call_delete(obj)
    if obj then obj:delete() end
end

function dfhack.with_temp_object(obj,fn,...)
    return dfhack.call_with_finalizer(1,true,call_delete,obj,fn,obj,...)
end

-- Module loading

function mkmodule(module,env)
    local pkg = package.loaded[module]
    if pkg == nil then
        pkg = {}
    else
        if type(pkg) ~= 'table' then
            error("Not a table in package.loaded["..module.."]")
        end
    end
    local plugname = string.match(module,'^plugins%.(%w+)$')
    if plugname then
        dfhack.open_plugin(pkg,plugname)
    end
    setmetatable(pkg, { __index = (env or _G) })
    return pkg
end

function reload(module)
    if type(package.loaded[module]) ~= 'table' then
        error("Module not loaded: "..module)
    end
    local path,err = package.searchpath(module,package.path)
    if not path then
        error(err)
    end
    dofile(path)
end

-- Misc functions

function printall(table)
    if type(table) == 'table' or df.isvalid(table) == 'ref' then
        for k,v in pairs(table) do
            print(string.format("%-23s\t = %s",tostring(k),tostring(v)))
        end
    end
end

function copyall(table)
    local rv = {}
    for k,v in pairs(table) do rv[k] = v end
    return rv
end

function pos2xyz(pos)
    local x = pos.x
    if x and x ~= -30000 then
        return x, pos.y, pos.z
    end
end

function xyz2pos(x,y,z)
    if x then
        return {x=x,y=y,z=z}
    else
        return {x=-30000,y=-30000,z=-30000}
    end
end

function dfhack.event:__tostring()
    return "<event>"
end

function dfhack.persistent:__tostring()
    return "<persistent "..self.entry_id..":"..self.key.."=\""
           ..self.value.."\":"..table.concat(self.ints,",")..">"
end

function dfhack.matinfo:__tostring()
    return "<material "..self.type..":"..self.index.." "..self:getToken()..">"
end

function dfhack.maps.getSize()
    local map = df.global.world.map
    return map.x_count_block, map.y_count_block, map.z_count_block
end

function dfhack.maps.getTileSize()
    local map = df.global.world.map
    return map.x_count, map.y_count, map.z_count
end

-- Interactive

local print_banner = true

function dfhack.interpreter(prompt,hfile,env)
    if not dfhack.is_interactive() then
        return nil, 'not interactive'
    end

    print("Type quit to exit interactive lua interpreter.")

    if print_banner then
        print("Shortcuts:\n"..
              " '= foo' => '_1,_2,... = foo'\n"..
              " '! foo' => 'print(foo)'\n"..
              "Both save the first result as '_'.")
        print_banner = false
    end

    local prompt_str = "["..(prompt or 'lua').."]# "
    local prompt_env = {}
	local t_prompt
    local vcnt = 1

    setmetatable(prompt_env, { __index = env or _G })
	local cmdlinelist={}
    while true do
        local cmdline = dfhack.lineedit(t_prompt or prompt_str, hfile)

        if cmdline == nil or cmdline == 'quit' then
            break
        elseif cmdline ~= '' then
            local pfix = string.sub(cmdline,1,1)

            if pfix == '!' or pfix == '=' then
                cmdline = 'return '..string.sub(cmdline,2)
            end
			table.insert(cmdlinelist,cmdline)
            local code,err = load(table.concat(cmdlinelist,'\n'), '=(interactive)', 't', prompt_env)

            if code == nil then
				if err:sub(-5)=="<eof>" then
					t_prompt="[cont]"
					
				else
					dfhack.printerr(err)
					cmdlinelist={}
					t_prompt=nil
				end
            else
			
				cmdlinelist={}
				t_prompt=nil
				
                local data = table.pack(safecall(code))

                if data[1] and data.n > 1 then
                    prompt_env._ = data[2]

                    if pfix == '!' then
                        safecall(print, table.unpack(data,2,data.n))
                    else
                        for i=2,data.n do
                            local varname = '_'..vcnt
                            prompt_env[varname] = data[i]
                            dfhack.print(varname..' = ')
                            safecall(print, data[i])
                            vcnt = vcnt + 1
                        end
                    end
                end
            end
        end
    end

    return true
end

-- Feed the table back to the require() mechanism.
return dfhack