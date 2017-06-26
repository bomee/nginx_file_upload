package.path = '/usr/local/share/lua/5.1/?.lua;/data/openresty/lualib/resty/?.lua;'
package.cpath = '/usr/local/lib/lua/5.1/?.so;'

local upload = require "upload"

local chunk_size = 8192 
local form,err = upload:new(chunk_size)
if not form then
    ngx.log(ngx.ERR, "failed to new upload: ", err)
    ngx.exit(500)
end

local file
local filelen=0
form:set_timeout(0) -- 1 sec
local filename

function get_filename(res)
    local filename = ngx.re.match(res,'(.+)filename="(.+)"(.*)')
    if filename then
        return filename[2]
    end
end

function get_param_name(res)
    if not res then
        return nil
    end
    local name = ngx.re.match(res,'(\\W+)name="(.+)"(.*)')
    if name then
        return name[2]
    end
end

function get_file_folder(file)
    local folder = ngx.re.match(file, '(.+)/[^/]+')
    if folder then
        return folder[1]
    end
end

function get_file_ext(file)
    local ext = ngx.re.match(file, '(.+)(\\.\\w+)')
    if ext then
        return ext[2]
    end
end

function res_error(msg)
 ngx.say("{\"code\":-1, \"msg\": \"" .. msg .."\"}")
end

function res_success()
 ngx.say("{\"code\":0, \"path\": \"" .. filename .."\"}")
end

local osfilepath = "/data/nginx/static"
local i=0
local params = {}
local resize = {}
local param_name
ngx.header.content_type = "text/plain"

if ngx.var.arg_path then
    params["path"] = ngx.var.arg_path
end

local t = tonumber(ngx.var.arg_t)
local key = ngx.var.arg_key
-- 这里没有引用身份验证，则用简单的字符串做验证
if t == nil or "xxxxx"~=key or (os.time() - t / 1000) > 300  then
    ngx.status = 403
    res_error("invalid")
    ngx.exit(403)
    return 
end


while true do
    local typ, res, err = form:read()
    if not typ then
        return res_error("failed to read: " .. err);
    end
    if typ == "header" then
        param_name = get_param_name(res[2])
        if res[1] ~= "Content-Type" then
            filename = get_filename(res[2])
            if filename then
                i=i+1
                if params["path"] and params["path"] ~= ""  then
                filename = params["path"]
             else
                -- 根据日期生成文件名
                filename = os.date('/%Y/%m/%d/') .. string.format('%02x', os.time()) .. string.format('%02x', math.random(256)) .. get_file_ext(filename) 
             end
             
             if string.sub(filename,1,1) ~= "/" then
                filename = "/" .. filename
             end
             filepath = osfilepath  .. filename
             os.execute('mkdir -p ' .. get_file_folder(filepath))
             file = io.open(filepath, "w+")
             if not file then
                return res_error("failed to open file")
            end
        else
        end
    end
    elseif typ == "body" then
        if file then
            filelen= filelen + tonumber(string.len(res))
            file:write(res)
        elseif param_name then
            params[param_name] = res
            if param_name == "resize" or param_name == "crop" then
                resize[param_name] = res
            end
        end
    elseif typ == "part_end" then
    if file then
        file:close()
        file = nil
        for h,v in pairs(resize) do
            if h == "resize" then
                os.execute("gm convert -resize " .. v .. " " .. filepath .. " " .. filepath .. "_" .. v .. get_file_ext(filename))
            end
            if h == "crop" then
                os.execute("gm convert -resize " .. v .. "^ -gravity center -extent " .. v .. " "  .. filepath .. " " .. filepath .. "_" .. v .. get_file_ext(filename))
            end
        end
        res_success()
    end
    elseif typ == "eof" then
        break
    else
    end
end

if i==0 then
    res_error("miss file")
    return
end

