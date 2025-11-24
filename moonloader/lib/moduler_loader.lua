script_name("moduler")
script_description("moduler loader")
script_author("MahdiMz")
script_url("https://github.com/MahdiMz80/Moduler")

local loadTryMax = 2

function string:trim() return self:match("^%s*(.-)%s*$") end
function noExt(str) str = str:gsub("%.+", ".") if str:lower():match("%.luac$") then str = str:sub(1, -6) elseif str:lower():match("%.lua$") then str = str:sub(1, -5) end return str end

local parent = getWorkingDirectory().."/moduler" if not doesDirectoryExist(parent) then createDirectory(parent) end

function printErr(msg) print("{ff7070}(error): {c0c0c0}"..msg) end

function isScrLoaded(scr) for i, s in pairs(script.list()) do if noExt(s.name:lower():trim()) == noExt(scr:lower():trim()) then return s end end return false end

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
		local chunk, err = loadstring(scrContent, scr..".lua")
		if not chunk then printErr("Syntax error in "..scr..": "..err) return false end

		local ok, execErr = pcall(chunk)
		if not ok then printErr(string.format('Error executing script: "%s": %s', scr, execErr)) return false end
		return true
	end
	
	print('{44bbff}Moduler: {c0c0c0}Building "'..scr..'" with '..#modulerCalls..' module calls...')
	
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

	local finalOk, finalExecErr = pcall(function() script.load(finalFilePath) end)
	if not finalOk then printErr("Error loading the built "..scr..": "..finalExecErr) return false end

	print('{44bbff}Moduler: {c0c0c0}Successfully built and loaded "'..scr..'"')
	return true
end

local loadTry = 0
function _load(scr)
	loadTry = loadTry + 1
	if loadTry > loadTryMax then return false end

	local already = isScrLoaded(scr)
	if already then
		local ok = pcall(function() already:unload() end)
		if not ok then printErr("Failed Unloading: "..scr) return false end

		local loadOk, loadErr = pcall(lua_thread.create, function()
			wait(100)
			_load(scr)
		end)
		return false
	end

	local root = getWorkingDirectory()
	local parent = root.."/moduler"
	local folder = parent.."/"..scr

	if not doesDirectoryExist(parent) then createDirectory(parent) printErr('No Modules found for "'..scr..'"') return false end
	if not doesDirectoryExist(folder) then printErr('No Modules found for "'..scr..'"') return false end

	return build(scr)
end

function load(scr)
	loadTry = 0
	local scr = scr and noExt(scr:trim()) or nil
	if not scr or scr == "" or scr:lower() == "moduler" then return false end

	return _load(scr)
end

function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(0) end

	sampRegisterChatCommand("moduler", function(scr)
		local scr = scr and noExt(scr:trim()) or nil
		if not scr or scr == "" or scr:lower() == "moduler" then return false end
		load(scr)
	end)
	
	while true do wait(0) end
end

EXPORTS = {
	load = load
}
