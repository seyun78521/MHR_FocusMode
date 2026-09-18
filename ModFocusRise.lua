--[[
    ModFocusRise.lua  -  Focus Aim for Monster Hunter Rise (REFramework)

    설치: <MHRise 폴더>/reframework/autorun/ModFocusRise.lua
    설정: 게임 내 REFramework 창(Insert 키) -> "Focus Aim (Rise)" 트리 노드

    원본 아이디어: ModFocusMHW (Focus Aim) by KhogaFTW (SharpPluginLoader / MHW)
    RE Engine 재구현: 회전 적용부는 환경에 따라 튜닝이 필요합니다. 아래 APPLY 섹션 참고.
--]]

--==========================================================================
-- 1. 설정 (Config)
--==========================================================================

local CFG_PATH = "ModFocusRise.json"

local DEFAULTS = {
    enabled     = true,
    mode        = 1,        -- 1 = 홀드, 2 = 토글
    key         = 0xA4,     -- VK_LMENU (LALT)
    align_to    = 1,        -- 1 = 카메라 정면, 2 = 락온 타겟
    smooth      = 0.35,     -- 0.0 = 즉시 스냅, 1.0 = 거의 안 돌아감
    yaw_offset  = 0.0,      -- 캐릭터가 180도 반대로 보면 3.14159 입력
    debug       = false,
}

local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

local function save_cfg()
    json.dump_file(CFG_PATH, cfg)
end

--==========================================================================
-- 2. 키 이름 테이블 (Windows VK 코드 = RE Engine via.hid.KeyboardKey 와 거의 동일)
--==========================================================================

local KEY_NAMES = {
    [0x08]="BACKSPACE", [0x09]="TAB",    [0x0D]="ENTER",  [0x10]="SHIFT",
    [0x11]="CTRL",      [0x12]="ALT",    [0x14]="CAPS",   [0x1B]="ESC",
    [0x20]="SPACE",     [0x21]="PGUP",   [0x22]="PGDN",   [0x23]="END",
    [0x24]="HOME",      [0x25]="LEFT",   [0x26]="UP",     [0x27]="RIGHT",
    [0x28]="DOWN",      [0x2D]="INSERT", [0x2E]="DELETE",
    [0xA0]="LSHIFT",    [0xA1]="RSHIFT", [0xA2]="LCTRL",  [0xA3]="RCTRL",
    [0xA4]="LALT",      [0xA5]="RALT",
}
for i = 0x30, 0x39 do KEY_NAMES[i] = string.char(i) end            -- 0-9
for i = 0x41, 0x5A do KEY_NAMES[i] = string.char(i) end            -- A-Z
for i = 1, 12     do KEY_NAMES[0x6F + i] = "F" .. i end            -- F1-F12

local function key_name(vk)
    return KEY_NAMES[vk] or string.format("0x%02X", vk)
end

--==========================================================================
-- 3. 입력 (via.hid.Keyboard)
--==========================================================================

local kb_singleton, kb_tdef
local key_prev_down = false

local function get_keyboard()
    if not kb_singleton then
        kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
        kb_tdef      = sdk.find_type_definition("via.hid.Keyboard")
    end
    if not kb_singleton then return nil end
    return sdk.call_native_func(kb_singleton, kb_tdef, "get_Device")
end

-- 눌려 있는 동안 계속 true (홀드용)
local function key_down(vk)
    local d = get_keyboard()
    if not d then return false end
    local ok, result = pcall(function()
        return d:call("isDown", vk) == true
    end)
    if not ok then
        last_error = "keyboard isDown: " .. tostring(result)
        return false
    end
    return result
end

-- 눌린 그 프레임에만 true (토글용)
local function key_trg(vk)
    local d = get_keyboard()
    if not d then return false end
    local ok, result = pcall(function()
        return d:call("isDown", vk) == true
    end)
    if not ok then
        last_error = "keyboard isDown(toggle): " .. tostring(result)
        key_prev_down = false
        return false
    end
    local trg = result and not key_prev_down
    key_prev_down = result
    return trg
end

--==========================================================================
-- 4. 게임 오브젝트 접근
--==========================================================================

local function get_player()
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end
    return pm:call("findMasterPlayer")   -- snow.player.PlayerBase
end

local function get_transform(obj)
    if not obj then return nil end
    local go = obj:call("get_GameObject")
    if not go then return nil end
    return go:call("get_Transform")
end

local sm_singleton, sm_tdef

local function get_camera_transform()
    if not sm_singleton then
        sm_singleton = sdk.get_native_singleton("via.SceneManager")
        sm_tdef      = sdk.find_type_definition("via.SceneManager")
    end
    if not sm_singleton then return nil end

    local view = sdk.call_native_func(sm_singleton, sm_tdef, "get_MainView")
    if not view then return nil end
    local cam = view:call("get_PrimaryCamera")
    if not cam then return nil end
    return get_transform(cam)
end

--[[ 락온 타겟.
     주의: 라이즈의 락온 매니저 타입명은 버전(Rise / Sunbreak)에 따라 다릅니다.
     REFramework -> DeveloperTools -> ObjectExplorer 에서 "Lockon" 또는 "Camera"
     로 검색해 실제 싱글톤/필드명을 확인한 뒤 아래를 채워 넣으세요.
     찾기 전까지는 align_to = 1 (카메라 정면) 모드를 쓰시면 됩니다. --]]
local function get_target_position()
    return nil
end

--==========================================================================
-- 5. 수학
--==========================================================================

local function yaw_from_quat(q)
    -- Y-up 기준 yaw 추출
    return math.atan(2.0 * (q.w * q.y + q.x * q.z),
                     1.0 - 2.0 * (q.y * q.y + q.x * q.x))
end

local function quat_from_yaw(yaw)
    local h = yaw * 0.5
    return Quaternion.new(0.0, math.sin(h), 0.0, math.cos(h))
end

local function wrap_pi(a)
    while a >  math.pi do a = a - math.pi * 2.0 end
    while a < -math.pi do a = a + math.pi * 2.0 end
    return a
end

--==========================================================================
-- 6. 상태 머신 (홀드 / 토글)
--==========================================================================

local focus_active = false
local toggle_state = false
local binding_key  = false      -- 설정창에서 키 입력 대기중인지

re.on_frame(function()
    -- 키 바인딩 캡처 모드
    if binding_key then
        local d = get_keyboard()
        if d then
            for vk = 0x08, 0xFE do
                local ok, down = pcall(function()
                    return d:call("isDown", vk) == true
                end)
                if ok and down then
                    if vk ~= 0x1B then            -- ESC = 취소
                        cfg.key = vk
                        save_cfg()
                    end
                    key_prev_down = false
                    binding_key = false
                    break
                end
            end
        end
        focus_active = false
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        return
    end

    if cfg.mode == 2 then
        if key_trg(cfg.key) then toggle_state = not toggle_state end
        focus_active = toggle_state
    else
        focus_active = key_down(cfg.key)     -- 누르고 있는 동안만
    end
end)

--==========================================================================
-- 7. APPLY - 실제 회전 적용
--
--   LockScene 은 게임 로직(Behavior/Motion) 이후에 도는 지점이라
--   여기서 회전을 덮어써야 모션에 되돌려지지 않습니다.
--   그래도 씹히면 "UpdateMotion" 또는 "BeginRendering" 으로 바꿔 보세요.
--==========================================================================

local last_error = nil

re.on_application_entry("LockScene", function()
    if not focus_active then return end

    local ok, err = pcall(function()
        local player = get_player()
        if not player then return end

        local ptr = get_transform(player)
        if not ptr then return end

        local ppos = ptr:call("get_Position")
        local dx, dz

        if cfg.align_to == 2 then
            local tpos = get_target_position()
            if not tpos then return end
            dx, dz = tpos.x - ppos.x, tpos.z - ppos.z
        else
            local ctr = get_camera_transform()
            if not ctr then return end
            local cpos = ctr:call("get_Position")
            -- 카메라는 캐릭터 뒤에 있으므로 (플레이어 - 카메라) 가 전방 벡터
            dx, dz = ppos.x - cpos.x, ppos.z - cpos.z
        end

        if (dx * dx + dz * dz) < 0.0001 then return end

        local target_yaw = math.atan(dx, dz) + cfg.yaw_offset
        local cur_yaw    = yaw_from_quat(ptr:call("get_Rotation"))
        local new_yaw

        if cfg.smooth <= 0.001 then
            new_yaw = target_yaw
        else
            local diff = wrap_pi(target_yaw - cur_yaw)
            new_yaw = cur_yaw + diff * (1.0 - cfg.smooth)
        end

        ptr:call("set_Rotation", quat_from_yaw(new_yaw))
    end)

    if not ok then last_error = tostring(err) end
end)

--==========================================================================
-- 8. 설정창 (ImGui)
--==========================================================================

re.on_draw_ui(function()
    if not imgui.tree_node("Focus Aim (Rise)") then return end

    local changed, val

    changed, val = imgui.checkbox("모드 활성화", cfg.enabled)
    if changed then cfg.enabled = val; save_cfg() end

    changed, val = imgui.combo("작동 방식", cfg.mode, { "홀드 (누르는 동안만)", "토글" })
    if changed then cfg.mode = val; toggle_state = false; save_cfg() end

    imgui.text("현재 키: " .. key_name(cfg.key))
    imgui.same_line()
    if binding_key then
        imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
    elseif imgui.button("키 변경") then
        binding_key = true
    end

    changed, val = imgui.combo("정렬 기준", cfg.align_to, { "카메라 정면", "락온 타겟" })
    if changed then cfg.align_to = val; save_cfg() end

    changed, val = imgui.slider_float("부드러움", cfg.smooth, 0.0, 0.95, "%.2f")
    if changed then cfg.smooth = val; save_cfg() end

    changed, val = imgui.slider_float("Yaw 보정(rad)", cfg.yaw_offset, -3.15, 3.15, "%.3f")
    if changed then cfg.yaw_offset = val; save_cfg() end

    changed, val = imgui.checkbox("디버그 표시", cfg.debug)
    if changed then cfg.debug = val; save_cfg() end

    if cfg.debug then
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("keyboard: " .. tostring(get_keyboard() ~= nil))
        imgui.text("key: " .. key_name(cfg.key) .. " (" .. tostring(cfg.key) .. ")")
        imgui.text("key_down: " .. tostring(key_down(cfg.key)))
        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.tree_pop()
end)

log.info("[ModFocusRise] loaded. key=" .. key_name(cfg.key))
