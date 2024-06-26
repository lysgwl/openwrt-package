local ipc = require "luci.ip"
local ut = require "luci.util"

local m = Map("eqos", translate("Quality of Service"))

local s = m:section(TypedSection, "eqos", "")
s.anonymous = true

local e = s:option(Flag, "enabled", translate("Enable"))
e.rmempty = false

local dl = s:option(Value, "download", translate("Download speed (Mbit/s)"), translate("Total bandwidth"))
dl.datatype = "and(uinteger,min(1))"

local ul = s:option(Value, "upload", translate("Upload speed (Mbit/s)"), translate("Total bandwidth"))
ul.datatype = "and(uinteger,min(1))"

s = m:section(TypedSection, "device", translate("Speed limit based on IP address"))
s.template = "cbi/tblsection"
s.anonymous = true
s.addremove = true
s.sortable  = true

local ip = s:option(Value, "ip", translate("IP address"))

local lan = ut.exec("uci get wiwiz.portal.lan 2>/dev/null")
if lan == "" then
	lan = "br-lan"
end

ipc.neighbors({family = 4, dev = lan}, function(n)
	if n.mac and n.dest then
		ip:value(n.dest:string(), "%s (%s)" %{ n.dest:string(), n.mac })
	end
end)

dl = s:option(Value, "download", translate("Download speed (Kbit/s)"))
dl.datatype = "and(uinteger,min(1))"

ul = s:option(Value, "upload", translate("Upload speed (Kbit/s)"))
ul.datatype = "and(uinteger,min(1))"

comment = s:option(Value, "comment", translate("Comment"))

return m
