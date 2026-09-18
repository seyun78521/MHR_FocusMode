--[[
    ModFocusRise v2.3 - Focus Aim for Monster Hunter Rise (REFramework)

    v2.3: 무기 구별은 일단 보류하고, Better Focus Mode의 11종 근접무기
    correction window 평균값을 모든 무기에 공통 적용합니다.

    평균 = 2.16 / 11 = 0.19636초 → 기본값 0.196초.

    현재 기능:
      - LALT로 집중모드 활성화
      - 이동만으로는 회전하지 않음
      - 공격 시작 시 카메라 방향을 저장
      - 평균 correction window 동안 저장 방향으로 보정
      - window 종료 후 일반 게임 회전에 반환

    v2.2의 무기 자동 판별/내부 필드 진단 코드는 제거했습니다.
    오버레이도 실제 사용에 필요한 항목만 남겼습니다.
]]

--==========================================================================
-- 1. 설정
--==========================================================================

local CFG_PATH = "ModFocusRise.json"

local DEFAULTS = {
    enabled        = true,
    mode           = 1,
    key            = 0xA4,
    key_name       = "Menu",   -- via.hid.KeyboardKey.Menu = LALT
    smooth         = 0.20,
    yaw_offset     = 0.0,

    debug          = false,
    apply_rotation = false,

    -- 11개 무기 timing의 평균값: 0.19636초 → 0.196초
    correction_window_seconds = 0.196,

    -- 기본 0.00: correction window 종료 후 즉시 게임 회전에 반환
    post_window_hold_seconds = 0.00,
}

local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

local function save_cfg()
    json.dump_file(CFG_PATH, cfg)
end

--==========================================================================
-- 2. 키 표시
--==========================================================================

local function key_display_name()
    if cfg.key_name == "Menu" then
        return "LALT"
    end
    return tostring(cfg.key_name or "Menu")
end

--==========================================================================
-- 3. Keyboard 입력
--==========================================================================

local kb_singleton, kb_tdef, kb_key_tdef
local key_prev_down = false
local input_error = nil

local function get_keyboard()
    if not kb_singleton then
        kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
        kb_tdef      = sdk.find_type_definition("via.hid.Keyboard")
        kb_key_tdef  = sdk.find_type_definition("via.hid.KeyboardKey")
    end

    if not kb_singleton or not kb_tdef or not kb_key_tdef then
        return nil
    end

    return sdk.call_native_func(kb_singleton, kb_tdef, "get_Device")
end

local function get_key_value(name)
    if not kb_key_tdef or not name then return nil end

    local field = kb_key_tdef:get_field(name)
    if not field then return nil end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)
    if not ok then return nil end

    return value
end

local function get_bound_key_value()
    local v = get_key_value(cfg.key_name or "Menu")
    if v == nil then
        input_error = "KeyboardKey not found: " .. tostring(cfg.key_name)
    end
    return v
end

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

local function key_trg()
    local now_down = key_down()
    local trg = now_down and not key_prev_down
    key_prev_down = now_down
    return trg
end

local function capture_key()
    local d = get_keyboard()
    if not d or not kb_key_tdef then return false end

    for _, field in ipairs(kb_key_tdef:get_fields()) do
        if field:is_static() then
            local name = field:get_name()
            local ok_value, value = pcall(function()
                return field:get_data(nil)
            end)

            if ok_value and value ~= nil then
                local ok_down, down = pcall(function()
                    return d:call("isDown", value) == true
                end)

                if ok_down and down then
                    if name ~= "Escape" then
                        cfg.key_name = name
                        cfg.key = value
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
-- 4. Mouse 입력
--==========================================================================

local mouse_singleton, mouse_tdef, mouse_button_tdef
local mouse_prev_l = false
local mouse_prev_r = false
local mouse_error = nil

local function get_mouse()
    if not mouse_singleton then
        mouse_singleton   = sdk.get_native_singleton("via.hid.Mouse")
        mouse_tdef        = sdk.find_type_definition("via.hid.Mouse")
        mouse_button_tdef = sdk.find_type_definition("via.hid.MouseButton")
    end

    if not mouse_singleton or not mouse_tdef or not mouse_button_tdef then
        return nil
    end

    return sdk.call_native_func(mouse_singleton, mouse_tdef, "get_Device")
end

local function get_mouse_button_value(name)
    if not mouse_button_tdef or not name then return nil end

    local field = mouse_button_tdef:get_field(name)
    if not field then
        mouse_error = "MouseButton not found: " .. tostring(name)
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)

    if not ok then
        mouse_error = "MouseButton get_data: " .. tostring(value)
        return nil
    end

    return value
end

local function mouse_down(name)
    local m = get_mouse()
    if not m then return false end

    local button = get_mouse_button_value(name)
    if button == nil then return false end

    local ok, result = pcall(function()
        return m:call("isDown", button) == true
    end)

    if not ok then
        mouse_error = "mouse isDown: " .. tostring(result)
        return false
    end

    return result
end

local function update_attack_input()
    local l = mouse_down("L")
    local r = mouse_down("R")

    local trg_l = l and not mouse_prev_l
    local trg_r = r and not mouse_prev_r

    mouse_prev_l = l
    mouse_prev_r = r

    return trg_l or trg_r, l, r
end

--==========================================================================
-- 5. Player / Camera
--==========================================================================

local function get_player()
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end
    return pm:call("findMasterPlayer")
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

    if not sm_singleton or not sm_tdef then return nil end

    local view = sdk.call_native_func(sm_singleton, sm_tdef, "get_MainView")
    if not view then return nil end

    local cam = view:call("get_PrimaryCamera")
    if not cam then return nil end

    return get_transform(cam)
end


--==========================================================================

-- 7. 수학
--==========================================================================

local function yaw_from_quat(q)
    return math.atan(
        2.0 * (q.w * q.y + q.x * q.z),
        1.0 - 2.0 * (q.y * q.y + q.x * q.x)
    )
end

-- REFramework Quaternion.new는 (w, x, y, z)
local function quat_from_yaw(yaw)
    local h = yaw * 0.5
    return Quaternion.new(
        math.cos(h),
        0.0,
        math.sin(h),
        0.0
    )
end

local function wrap_pi(a)
    while a >  math.pi do a = a - math.pi * 2.0 end
    while a < -math.pi do a = a + math.pi * 2.0 end
    return a
end

--==========================================================================
-- 8. 상태
--==========================================================================

local focus_active = false
local toggle_state = false
local binding_key  = false

local attack_correction_active = false
local attack_locked_yaw = nil
local attack_window_remaining = 0.0
local current_window_seconds = 0.196
local attack_triggered = false
local post_window_hold_remaining = 0.0

local last_error = nil
local apply_count = 0
local frame_id = 0
local last_apply_frame = -1

-- 게임의 실제 DeltaTime을 사용해 초 단위 correction window 유지.
-- 실패 시 60 FPS 기준으로 fallback.
local app_singleton, app_tdef
local function get_delta_time()
    if not app_singleton then
        app_singleton = sdk.get_native_singleton("via.Application")
        app_tdef = sdk.find_type_definition("via.Application")
    end

    if app_singleton and app_tdef then
        local ok, dt = pcall(function()
            return sdk.call_native_func(app_singleton, app_tdef, "get_DeltaTime")
        end)
        if ok and type(dt) == "number" and dt > 0.0 and dt < 0.25 then
            return dt
        end
    end

    return 1.0 / 60.0
end

local function reset_attack_correction()
    attack_correction_active = false
    attack_locked_yaw = nil
    attack_window_remaining = 0.0
    attack_triggered = false
    post_window_hold_remaining = 0.0
end

--==========================================================================
-- 9. 상태 머신
--==========================================================================

re.on_frame(function()
    frame_id = frame_id + 1
    attack_triggered = false

    if binding_key then
        if capture_key() then
            binding_key = false
        end

        focus_active = false
        reset_attack_correction()
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        mouse_prev_l = false
        mouse_prev_r = false
        reset_attack_correction()
        return
    end

    if cfg.mode == 2 then
        if key_trg() then
            toggle_state = not toggle_state
        end
        focus_active = toggle_state
    else
        focus_active = key_down()
    end

    local attack_trg = false
    if get_mouse() ~= nil then
        attack_trg = update_attack_input()
    end

    if focus_active and attack_trg then
        local ok, err = pcall(function()
            local player = get_player()
            local ptr = get_transform(player)
            local ctr = get_camera_transform()

            if not player or not ptr or not ctr then
                return false
            end

            local ppos = ptr:call("get_Position")
            local cpos = ctr:call("get_Position")
            local dx = ppos.x - cpos.x
            local dz = ppos.z - cpos.z

            if (dx * dx + dz * dz) < 0.0001 then
                return false
            end

            -- 공격이 시작되는 바로 그 순간의 카메라 방향을 저장.
            attack_locked_yaw = math.atan(dx, dz) + cfg.yaw_offset
            current_window_seconds = math.max(0.01, cfg.correction_window_seconds)
            attack_window_remaining = current_window_seconds
            attack_correction_active = true
            attack_triggered = true
            return true
        end)

        if not ok then
            last_error = "attack trigger: " .. tostring(err)
        end
    end

    -- 시간 기반 correction window. 실제 게임 DeltaTime을 사용.
    if attack_correction_active then
        attack_window_remaining = attack_window_remaining - get_delta_time()

        if attack_window_remaining <= 0.0 then
            attack_window_remaining = 0.0
            attack_correction_active = false
            if cfg.post_window_hold_seconds > 0.0 then
                post_window_hold_remaining = cfg.post_window_hold_seconds
            else
                attack_locked_yaw = nil
            end
        end
    elseif post_window_hold_remaining > 0.0 then
        post_window_hold_remaining = post_window_hold_remaining - get_delta_time()
        if post_window_hold_remaining <= 0.0 then
            post_window_hold_remaining = 0.0
            attack_locked_yaw = nil
        end
    end
end)

--==========================================================================
-- 10. APPLY - 공격 시작 방향 유지
--==========================================================================

local function apply_locked_yaw()
    if not attack_correction_active and post_window_hold_remaining <= 0.0 then return end
    if attack_locked_yaw == nil then return end
    if not cfg.apply_rotation then return end

    local player = get_player()
    if not player then return end

    local ptr = get_transform(player)
    if not ptr then return end

    local current_rotation = ptr:call("get_Rotation")
    local cur_yaw = yaw_from_quat(current_rotation)
    local diff = wrap_pi(attack_locked_yaw - cur_yaw)

    local delta_yaw
    if cfg.smooth <= 0.001 then
        delta_yaw = diff
    else
        delta_yaw = diff * (1.0 - cfg.smooth)
    end

    local max_step = math.pi * 0.5
    if delta_yaw > max_step then delta_yaw = max_step end
    if delta_yaw < -max_step then delta_yaw = -max_step end

    local yaw_delta_quat = quat_from_yaw(delta_yaw)
    local new_rotation = (yaw_delta_quat * current_rotation):normalized()

    ptr:call("set_Rotation", new_rotation)
    apply_count = apply_count + 1
end

re.on_pre_application_entry("LockScene", function()
    if not attack_correction_active and post_window_hold_remaining <= 0.0 then return end
    if not cfg.apply_rotation then return end

    if last_apply_frame == frame_id then return end
    last_apply_frame = frame_id

    local ok, err = pcall(apply_locked_yaw)
    if not ok then
        last_error = "apply rotation: " .. tostring(err)
    end
end)

--==========================================================================
--==========================================================================
-- 11. UI
--==========================================================================

re.on_draw_ui(function()
    if not imgui.tree_node("Focus Aim (Rise)") then return end

    local changed, val

    changed, val = imgui.checkbox("모드 활성화", cfg.enabled)
    if changed then cfg.enabled = val; save_cfg() end

    changed, val = imgui.combo("작동 방식", cfg.mode, {
        "홀드 (누르는 동안만)",
        "토글"
    })
    if changed then
        cfg.mode = val
        toggle_state = false
        reset_attack_correction()
        save_cfg()
    end

    imgui.text("현재 키: " .. key_display_name())
    imgui.same_line()
    if binding_key then
        imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
    elseif imgui.button("키 변경") then
        binding_key = true
    end

    changed, val = imgui.slider_float("부드러움", cfg.smooth, 0.0, 0.95, "%.2f")
    if changed then cfg.smooth = val; save_cfg() end

    changed, val = imgui.slider_float("Yaw 보정(rad)", cfg.yaw_offset, -3.15, 3.15, "%.3f")
    if changed then cfg.yaw_offset = val; save_cfg() end

    imgui.separator()
    imgui.text("공격 시작 보정")
    imgui.text("전체 무기 평균: 0.196초")

    changed, val = imgui.slider_float(
        "보정 시간(초)",
        cfg.correction_window_seconds,
        0.05,
        0.50,
        "%.3f"
    )
    if changed then cfg.correction_window_seconds = val; save_cfg() end

    changed, val = imgui.checkbox("디버그 표시", cfg.debug)
    if changed then cfg.debug = val; save_cfg() end

    changed, val = imgui.checkbox("회전 적용", cfg.apply_rotation)
    if changed then cfg.apply_rotation = val; save_cfg() end

    if cfg.debug then
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))
        imgui.text("correction active: " .. tostring(attack_correction_active))
        imgui.text("window remaining: " .. string.format("%.3f", attack_window_remaining) .. " sec")
        imgui.text("apply_rotation: " .. tostring(cfg.apply_rotation))
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.tree_pop()
end)

log.info(
    "[ModFocusRise v2.3] loaded. window=" ..
    tostring(cfg.correction_window_seconds) .. " sec, key=" .. tostring(key_display_name())
)
