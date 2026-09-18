--[[
    ModFocusRise v1.9  -  Focus Aim for Monster Hunter Rise (REFramework)
    v1.9: 정지 중 회전 추적을 막고, 캐릭터가 이동/회전한 뒤 잠시 동안만 카메라 방향을 따라가도록 활동 감지를 추가.

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
    smooth      = 0.35,     -- 0.0 = 즉시 스냅, 1.0 = 거의 안 돌아감
    yaw_offset  = 0.0,      -- 캐릭터가 180도 반대로 보면 3.14159 입력
    debug       = false,
    apply_rotation = false,  -- v1.4: 안전 진단용. 기본 OFF
    activity_gate = true,     -- v1.9: 이동/행동 중에만 회전 적용
    activity_pos_threshold = 0.01, -- 프레임당 위치 변화량(미터)
    activity_yaw_threshold = 0.015, -- 프레임당 회전 변화량(rad)
    activity_hold_frames = 12, -- 활동 감지 후 회전을 유지할 프레임 수
}

local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

-- 기존 VK 코드 설정(0xA4)은 새 enum 방식으로 마이그레이션합니다.
if cfg.key_name == nil then
    cfg.key_name = "Menu"  -- via.hid.KeyboardKey.Menu = Alt 계열
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
--
-- REFramework의 via.hid.Keyboard는 Windows VK 코드(예: 0xA4)를
-- 그대로 받는다고 가정하지 않고, via.hid.KeyboardKey enum 값을
-- 사용하는 것이 안전합니다. 기본키는 KeyboardKey.Menu(Alt)로 잡습니다.
--==========================================================================

local kb_singleton, kb_tdef
local kb_key_tdef
local key_prev_down = false
local input_error = nil

local function get_keyboard()
    if not kb_singleton then
        kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
        kb_tdef      = sdk.find_type_definition("via.hid.Keyboard")
        kb_key_tdef  = sdk.find_type_definition("via.hid.KeyboardKey")
    end
    if not kb_singleton or not kb_tdef or not kb_key_tdef then return nil end
    return sdk.call_native_func(kb_singleton, kb_tdef, "get_Device")
end

local function get_key_value(name)
    if not kb_key_tdef or not name then return nil end
    local field = kb_key_tdef:get_field(name)
    if not field then return nil end
    local ok, value = pcall(function() return field:get_data(nil) end)
    if not ok then return nil end
    return value
end

local function key_name_value()
    return cfg.key_name or "Menu"
end

-- REFramework KeyboardKey의 실제 enum 이름은 Menu지만,
-- 사용자가 보는 UI에서는 실제 의도한 키인 LALT로 표시합니다.
local function key_display_name()
    local name = key_name_value()
    if name == "Menu" then
        return "LALT"
    end
    return name
end

local function get_bound_key_value()
    local v = get_key_value(key_name_value())
    if v == nil then
        input_error = "KeyboardKey not found: " .. tostring(key_name_value())
    end
    return v
end

-- 눌려 있는 동안 계속 true (홀드용)
local function key_down()
    local d = get_keyboard()
    if not d then return false end
    local key = get_bound_key_value()
    if key == nil then return false end
    local ok, result = pcall(function()
        return d:call("isDown", key) == true
    end)
    if not ok then
        input_error = "keyboard isDown: " .. tostring(result)
        return false
    end
    return result
end

-- 눌린 순간만 true (토글용)
local function key_trg()
    local now_down = key_down()
    local trg = now_down and not key_prev_down
    key_prev_down = now_down
    return trg
end

-- 현재 장치가 인식하는 KeyboardKey enum을 찾아 새 키를 바인딩합니다.
local function capture_key()
    local d = get_keyboard()
    if not d or not kb_key_tdef then return false end

    for _, field in ipairs(kb_key_tdef:get_fields()) do
        if field:is_static() then
            local name = field:get_name()
            local ok_value, value = pcall(function() return field:get_data(nil) end)
            if ok_value and value ~= nil then
                local ok_down, down = pcall(function()
                    return d:call("isDown", value) == true
                end)
                if ok_down and down then
                    -- ESC는 취소
                    if name ~= "Escape" then
                        cfg.key_name = name
                        cfg.key = value -- 호환/표시용으로 함께 저장
                        save_cfg()
                    end
                    key_prev_down = false
                    return true
                end
            end
        end
    end

    return false
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
    return Quaternion.new(math.cos(h), 0.0, math.sin(h), 0.0)
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

-- v1.9 활동 감지 상태
local activity_active = false
local activity_frames_left = 0
local activity_initialized = false
local activity_last_pos = nil
local activity_last_yaw = nil
local last_error = nil
local apply_count = 0
local frame_id = 0
local last_apply_frame = -1

local function reset_activity()
    activity_active = false
    activity_frames_left = 0
    activity_initialized = false
    activity_last_pos = nil
    activity_last_yaw = nil
end

local function copy_vec3(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function update_activity()
    if not cfg.activity_gate then
        activity_active = true
        return true
    end

    local player = get_player()
    local ptr = get_transform(player)
    if not ptr then
        activity_active = false
        return false
    end

    local ok, result = pcall(function()
        local pos = ptr:call("get_Position")
        local rot = ptr:call("get_Rotation")
        local yaw = yaw_from_quat(rot)

        if not activity_initialized or not activity_last_pos or activity_last_yaw == nil then
            activity_last_pos = copy_vec3(pos)
            activity_last_yaw = yaw
            activity_initialized = true
            activity_active = false
            return false
        end

        local dx = pos.x - activity_last_pos.x
        local dy = pos.y - activity_last_pos.y
        local dz = pos.z - activity_last_pos.z
        local moved = (dx * dx + dy * dy + dz * dz) >= (cfg.activity_pos_threshold * cfg.activity_pos_threshold)

        local yaw_delta = math.abs(wrap_pi(yaw - activity_last_yaw))
        local rotated = yaw_delta >= cfg.activity_yaw_threshold

        activity_last_pos = copy_vec3(pos)
        activity_last_yaw = yaw

        if moved or rotated then
            activity_frames_left = cfg.activity_hold_frames
        elseif activity_frames_left > 0 then
            activity_frames_left = activity_frames_left - 1
        end

        activity_active = activity_frames_left > 0
        return activity_active
    end)

    if not ok then
        last_error = "activity: " .. tostring(result)
        activity_active = false
        return false
    end

    return result
end

re.on_frame(function()
    -- 키 바인딩 캡처 모드
    if binding_key then
        if capture_key() then
            binding_key = false
        end
        focus_active = false
        reset_activity()
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        reset_activity()
        return
    end

    if cfg.mode == 2 then
        if key_trg() then toggle_state = not toggle_state end
        focus_active = toggle_state
    else
        focus_active = key_down()            -- 누르고 있는 동안만
    end

    if not focus_active then
        reset_activity()
    else
        update_activity()
    end
end)

--==========================================================================
-- 7. APPLY - 실제 회전 적용
--
--   LockScene 은 게임 로직(Behavior/Motion) 이후에 도는 지점이라
--   여기서 회전을 덮어써야 모션에 되돌려지지 않습니다.
--   그래도 씹히면 "UpdateMotion" 또는 "BeginRendering" 으로 바꿔 보세요.
--==========================================================================

-- 프레임마다 한 번만 회전 적용.
-- MHRise 예제에서 Transform 수정은 LockScene의 pre 단계에서 수행됩니다.
re.on_frame(function()
    frame_id = frame_id + 1
end)

re.on_pre_application_entry("LockScene", function()
    if not focus_active then return end
    if not cfg.apply_rotation then return end
    if cfg.activity_gate and not activity_active then return end

    -- LockScene이 한 프레임에 여러 번 들어오더라도 1회만 적용
    if last_apply_frame == frame_id then return end
    last_apply_frame = frame_id

    local ok, err = pcall(function()
        local player = get_player()
        if not player then return end

        local ptr = get_transform(player)
        if not ptr then return end

        local ppos = ptr:call("get_Position")
        local ctr = get_camera_transform()
        if not ctr then return end
        local cpos = ctr:call("get_Position")
        -- 카메라는 캐릭터 뒤에 있으므로 (플레이어 - 카메라) 가 전방 벡터
        local dx, dz = ppos.x - cpos.x, ppos.z - cpos.z

        if (dx * dx + dz * dz) < 0.0001 then return end

        local target_yaw = math.atan(dx, dz) + cfg.yaw_offset
        local current_rotation = ptr:call("get_Rotation")
        local cur_yaw = yaw_from_quat(current_rotation)
        local diff = wrap_pi(target_yaw - cur_yaw)

        local delta_yaw
        if cfg.smooth <= 0.001 then
            delta_yaw = diff
        else
            delta_yaw = diff * (1.0 - cfg.smooth)
        end

        -- 안전장치: 한 번의 적용에서 90도보다 크게 회전시키지 않음.
        -- 비정상적인 quaternion/동기화 상황에서 대형 회전으로 튀는 것을 방지합니다.
        local max_step = math.pi * 0.5
        if delta_yaw > max_step then delta_yaw = max_step end
        if delta_yaw < -max_step then delta_yaw = -max_step end

        local yaw_delta_quat = quat_from_yaw(delta_yaw)
        local new_rotation = (yaw_delta_quat * current_rotation):normalized()

        ptr:call("set_Rotation", new_rotation)
        apply_count = apply_count + 1
    end)

    if not ok then last_error = tostring(err) end
end)

--==========================================================================
-- 8. 설정창 (ImGui)
--==========================================================================

re.on_draw_ui(function()
    if not imgui.tree_node("Focus Aim (Rise)") then return end

    local changed, val

    changed, val = imgui.checkbox("Enable Mod", cfg.enabled)
    if changed then cfg.enabled = val; save_cfg() end

    changed, val = imgui.combo("Operation Mode", cfg.mode, { "Hold", "Toggle" })
    if changed then cfg.mode = val; toggle_state = false; save_cfg() end

    imgui.text("Current Key: " .. tostring(key_display_name()))
    imgui.same_line()
    if binding_key then
        imgui.text("  << Press any key (ESC to cancel)")
    elseif imgui.button("Change Key") then
        binding_key = true
    end

    changed, val = imgui.slider_float("Smoothness", cfg.smooth, 0.0, 0.95, "%.2f")
    if changed then cfg.smooth = val; save_cfg() end

    changed, val = imgui.slider_float("Yaw Offset (rad)", cfg.yaw_offset, -3.15, 3.15, "%.3f")
    if changed then cfg.yaw_offset = val; save_cfg() end

    changed, val = imgui.checkbox("Rotate Only During Activity", cfg.activity_gate)
    if changed then cfg.activity_gate = val; save_cfg(); reset_activity() end

    if cfg.activity_gate then
        changed, val = imgui.slider_float("Movement Sensitivity (m)", cfg.activity_pos_threshold, 0.001, 0.05, "%.3f")
        if changed then cfg.activity_pos_threshold = val; save_cfg() end

        changed, val = imgui.slider_float("Rotation Sensitivity (rad)", cfg.activity_yaw_threshold, 0.001, 0.10, "%.3f")
        if changed then cfg.activity_yaw_threshold = val; save_cfg() end

        changed, val = imgui.slider_int("Tracking Hold Frames", cfg.activity_hold_frames, 1, 60)
        if changed then cfg.activity_hold_frames = val; save_cfg() end
    end

    changed, val = imgui.checkbox("Show Debug Info", cfg.debug)
    if changed then cfg.debug = val; save_cfg() end

    changed, val = imgui.checkbox("Apply Rotation", cfg.apply_rotation)
    if changed then cfg.apply_rotation = val; save_cfg() end

    if cfg.debug then
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("keyboard: " .. tostring(get_keyboard() ~= nil))
        imgui.text("KeyboardKey: " .. tostring(key_display_name()))
        imgui.text("key value: " .. tostring(get_bound_key_value()))
        imgui.text("key_down: " .. tostring(key_down()))
        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))
        imgui.text("apply_rotation: " .. tostring(cfg.apply_rotation))
        imgui.text("activity_gate: " .. tostring(cfg.activity_gate))
        imgui.text("activity_active: " .. tostring(activity_active))
        imgui.text("activity_frames_left: " .. tostring(activity_frames_left))
        imgui.text("apply_count: " .. tostring(apply_count))
        if input_error then imgui.text("input error: " .. input_error) end
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.tree_pop()
end)

log.info("[ModFocusRise v1.9] loaded. KeyboardKey=" .. tostring(key_display_name()) .. ", apply_rotation=" .. tostring(cfg.apply_rotation))
