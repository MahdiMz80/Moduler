-- moduler library for splitting scripts into the modules and load them anywhere, with no need for changing the structure
-- Made by MahdiMz
-- https://github.com/MahdiMz80/Moduler
-- v2.0

--=================================
local useOldMethod = false

------------------------------
-- Only for old method:

local forceKill = true
local sendThroughCommand = false
--=================================

local loader_path = nil
function getLoaderPath() for i, s in pairs(script.list()) do if s.name:lower() == "moduler" then return s.path end end return false end
function loadModuler()
	local _loader_path = getWorkingDirectory().."\\lib\\moduler_loader.lua"
	if doesFileExist(_loader_path) then
		local fOk, fErr = pcall(function() script.load(_loader_path) end)
		if fOk then loader_path = _loader_path end
	end
end
if useOldMethod then
	loader_path = getLoaderPath()
	if not loader_path then loadModuler() end
	assert(loader_path, "Cannot load the moduler loader script.")
end

local EXPORTS = {}

function string:trim() return self:match("^%s*(.-)%s*$") end
function noExt(str) str = str:gsub("%.+", ".") if str:lower():match("%.luac$") then str = str:sub(1, -6) elseif str:lower():match("%.lua$") then str = str:sub(1, -5) end return str end

function printErr(msg) print("{ff7070}(error): {c0c0c0}"..msg) end

function extractSubmodule(moduleContent, subModule)
	local patterns = {"local%s+function%s+"..subModule.."%s*%b()", "function%s+"..subModule.."%s*%b()", "local%s+"..subModule.."%s*=%s*function%s*%b()", subModule.."%s*=%s*function%s*%b()"}

	local funcStart
	for _, pat in ipairs(patterns) do funcStart = moduleContent:find(pat) if funcStart then break end end
	
	if not funcStart then return nil end

	local bodyStart = moduleContent:find("%b()", funcStart)
	if not bodyStart then return nil end
	local _, bodyStart = moduleContent:find("%b()", funcStart)
	bodyStart = bodyStart + 1

	local pos, depth, foundFunction = funcStart, 0, false
	
	while pos <= #moduleContent do
		local word, wordEnd = moduleContent:match("^([%a_][%w_]*)()", pos)
		
		if word then
			if word == "function" or word == "do" or word == "if" or word == "for" or word == "while" or word == "repeat" then
				depth = depth + 1 if word == "function" then foundFunction = true end pos = wordEnd
			elseif word == "end" then
				if foundFunction then
					depth = depth - 1
					if depth == 0 then
						local body = moduleContent:sub(bodyStart, pos - 1):match("^[\r\n]*(.-)[ \t\r\n]*$") return body
					end
				end
				pos = wordEnd
			elseif word == "until" then
				depth = depth - 1 pos = wordEnd
			else
				pos = wordEnd
			end
		else
			pos = pos + 1
		end
	end
	
	return nil
end

function findModulerCalls(content)
	local calls = {}
	local pos = 1
	
	while true do
		local callStart, callEnd, module = content:find('moduler%s*%(%s*["\']([^"\']+)["\']%s*%)', pos)
		if not callStart then break end
		
		local lineStart = callStart
		while lineStart > 1 and content:sub(lineStart - 1, lineStart - 1):match('[^\r\n]') do
			lineStart = lineStart - 1
		end
		
		local lineFromStart = content:sub(lineStart)
		local indent = lineFromStart:match('^([ \t]*)')
		
		table.insert(calls, {module = module, indent = indent})
		pos = callEnd + 1
	end
	
	return calls
end

function applyIndentation(code, indent)
	local lines = {}
	for line in code:gmatch("[^\r\n]+") do table.insert(lines, line) end
	
	if #lines > 0 then
		local minIndent = nil
		for _, line in ipairs(lines) do
			if line:match("%S") then
				local lineIndent = line:match("^([ \t]*)")
				if not minIndent or #lineIndent < #minIndent then minIndent = lineIndent end
			end
		end
		
		if minIndent and #minIndent > 0 then
			local cleanedLines = {}
			for _, line in ipairs(lines) do
				if line:sub(1, #minIndent) == minIndent then
					table.insert(cleanedLines, line:sub(#minIndent + 1))
				else
					table.insert(cleanedLines, line)
				end
			end
			lines = cleanedLines
		end
	end
	
	if indent == "" then return table.concat(lines, "\n") end
	
	local indentedLines = {}
	for _, line in ipairs(lines) do table.insert(indentedLines, indent..line) end
	return table.concat(indentedLines, "\n")
end

function build(scr)
	scr = noExt(scr)
	
	local root = getWorkingDirectory()
	local parent = root.."/moduler"
	local folder = parent.."/"..scr
	local scrPath = root.."/"..scr..".lua"
	
	if not doesFileExist(scrPath) then printErr('Script "'..scr..'.lua" not found') return false end

	local scrFile = io.open(scrPath, "rb")
	if not scrFile then printErr("Error opening script: "..scr) return false end

	local scrContent = scrFile:read("*a")
	scrFile:close()
	if #scrContent == 0 then printErr(string.format('Script "%s" is empty.', scr)) return false end

	local scrHeader = scrContent:sub(1,4)
	if not scrHeader then printErr("No header found in script: "..scr) return false end
	if scrHeader == "\27Lua" or scrHeader == "\27LJ" then printErr(string.format('Script "%s" not supported as it is compiled. Use plain lua script.', scr)) return false end
	
	local modulerCalls = findModulerCalls(scrContent)
	
	if #modulerCalls == 0 then
		print('No moduler() calls found in "'..scr..'"')
		return true
	end
	
	print('{44bbff}Moduler: {c0c0c0}Building "'..scr..'" with '..#modulerCalls..' module calls...')
	
	EXPORTS = {}
	
	local injections = {}
	for _, callInfo in ipairs(modulerCalls) do
		local moduleCall, indent = callInfo.module, callInfo.indent
		local module = noExt(moduleCall)
		local subModule = nil
		
		if module:match("%.", 1, true) then
			local parts = {}
			for p in module:gmatch("[^%.]+") do table.insert(parts, p) end
			if #parts > 2 then
				printErr("Submodule nesting too deep: "..moduleCall)
				return false
			end
			module = parts[1]
			subModule = #parts == 2 and parts[2]:trim() or nil
		end
		
		local modulePath = folder.."/"..module..".lua"
		if not doesFileExist(modulePath) then printErr(string.format('Module "%s" not found for script "%s"', module, scr)) return false end

		local moduleFile = io.open(modulePath, "rb")
		if not moduleFile then printErr(string.format('Error opening module "%s" for script "%s"', module, scr)) return false end

		local moduleContent = moduleFile:read("*a")
		moduleFile:close()
		if #moduleContent == 0 then printErr(string.format('Module "%s" for script "%s" is empty.', module, scr)) return false end

		local moduleHeader = moduleContent:sub(1,4)
		if not moduleHeader then printErr(string.format('No header found in module "%s" for script "%s"', module, scr)) return false end
		if moduleHeader == "\27Lua" or moduleHeader == "\27LJ" then printErr(string.format('Module "%s" for script "%s" not supported as it is compiled. Use plain lua module.', module, scr)) return false end
		
		local codeToInject
		if subModule then
			codeToInject = extractSubmodule(moduleContent, subModule)
			if not codeToInject then printErr(string.format('Submodule "%s" not found in module "%s" for script "%s"', subModule, module, scr)) return false end
		else
			codeToInject = moduleContent
		end
		
		local testChunk, testErr = loadstring(codeToInject, "@"..module..(subModule and "."..subModule or ""))
		if not testChunk then printErr(string.format('Syntax error in "%s" for script "%s": %s', moduleCall, scr, testErr)) return false end
		
		local indentedCode = applyIndentation(codeToInject, indent)
		
		table.insert(injections, {
			marker = 'moduler%s*%(%s*["\']'..moduleCall:gsub("%.", "%%%.")..'["\']%s*%)',
			code = string.format("--[[START OF MODULER: %s]]\n%s\n%s--[[END OF MODULER: %s]]", moduleCall, indentedCode, indent, moduleCall)
		})

		if not EXPORTS[moduleCall] then EXPORTS[moduleCall] = codeToInject end
	end
	
	for _, injection in ipairs(injections) do
		scrContent = scrContent:gsub(injection.marker, injection.code)
	end

	scrContent = scrContent:gsub('require%s*%(%s*["\']moduler["\']%s*%)', '-- require("moduler") removed')
	
	local finalChunk, finalErr = loadstring(scrContent, scr..".lua")
	if not finalChunk then printErr(string.format('Syntax error in built script "%s": %s', scr, finalErr)) return false end

	local finalFilePath = parent.."\\"..scr.."_moduler.lua"
	local finalFile = io.open(finalFilePath, "wb")
	if not finalFile then printErr("Error writing the built script: "..scr) return false end
	finalFile:write(scrContent)
	finalFile:close()

	for moduleCall, rawCode in pairs(EXPORTS) do
		local chunk, err = loadstring(rawCode, "@"..moduleCall)
		if chunk then
			EXPORTS[moduleCall] = chunk
		else
			printErr(string.format('Syntax error in "%s": %s', moduleCall, err))
			EXPORTS[moduleCall] = nil
		end
	end

	-- for moduleCall, rawCode in pairs(EXPORTS) do
	-- 	local chunk, err = loadstring(rawCode, "@"..moduleCall)
	-- 	if chunk then
	-- 		local env = setmetatable({}, {__index = _G})
	-- 		setfenv(chunk, env)
			
	-- 		local ok, result = pcall(chunk)
	-- 		if ok then
	-- 			local funcName = moduleCall:match("%.([^%.]+)$") or moduleCall
	-- 			EXPORTS[moduleCall] = env[funcName] or chunk
	-- 		else
	-- 			printErr(string.format('Error loading "%s": %s', moduleCall, result))
	-- 			EXPORTS[moduleCall] = nil
	-- 		end
	-- 	else
	-- 		printErr(string.format('Syntax error in "%s": %s', moduleCall, err))
	-- 		EXPORTS[moduleCall] = nil
	-- 	end
	-- end
	
	print(string.format("{44bbff}Moduler: {c0c0c0}Loaded %d modules/submodules for '%s'", (function() local c=0 for _ in pairs(EXPORTS) do c=c+1 end return c end)(), scr))
	
	return true
end

function load(moduleCall)
	if not moduleCall or moduleCall == "" then printErr("Invalid module path") return nil end
	
	moduleCall = moduleCall:trim()
	
	local func = EXPORTS[moduleCall]
	if func and type(func) == "function" then
		return func()
	else
		printErr(string.format('Module "%s" not found', moduleCall))
		return nil
	end
end

local callerScript = thisScript().name
if not callerScript then error("Cannot get the name of the caller script.") end

_G.moduler = function() end

if not useOldMethod then
	local buildOk = build(callerScript)
	if not buildOk then error("Failed to build the final script.") end
	_G.moduler = load
else
	local thisScr = thisScript()
	local code = ""
	if sendThroughCommand then
		code = string.format([[
		lua_thread.create(function()
			wait(100)
			sampProcessChatInput("/moduler ".."%s")
			thisScript():unload()
		end)
		]], thisScr.name)
	else
		code = string.format([[
		require 'lib.moonloader'
		local moduler = import '%s'
		lua_thread.create(function()
			wait(100)
			moduler.load("%s")
			thisScript():unload()
		end)
		]], loader_path:gsub("\\", "\\\\"), thisScr.name)
	end
	local tmp = os.tmpname().."_moduler_requestload.lua"
	local f = io.open(tmp, "wb")
	f:write(code)
	f:close()
	local fOk, fErr = pcall(function() script.load(tmp) end)

	if forceKill then
		local unloadOk, unloadErr = pcall(function() thisScr:unload() end)
		error("_FORCE_KILL_THE_SCRIPT_")
	else
		lua_thread.create(function()
			wait(1)
			local unloadOk, unloadErr = pcall(function() thisScr:unload() end)
		end)
	end

	_G.moduler = function(module) local unloadOk, unloadErr = pcall(function() thisScr:unload() end) end
end

return _G.moduler
