--[[
    ModFocusRise v2.4 - Focus Aim for Monster Hunter Rise (REFramework)

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

    v2.4 추가사항 (실험용, 두 가지 모두 "10. APPLY" 문제 진단용):

      1) 회전 적용 시점을 코드 수정 없이 게임 내에서 바로 바꿔볼 수 있는
         콤보박스. LockScene pre/post, UpdateMotion pre/post, BeginRendering
         post 중 선택. "잠깐 보였다가 원래 방향으로 돌아감" 증상이 훅 타이밍
         때문인지 아닌지 1초 안에 A/B 테스트 가능.

      2) 필드/메서드 탐색기. PlayerBase 인스턴스의 실제 런타임 타입부터
         부모 타입 체인을 걸어 올라가며 필드/메서드 이름을 훑고, 키워드
         (angle, direction, rotat, action, motion, weapon, fsm 등)로 걸러
         오버레이에 실시간으로 뿌려줍니다. ObjectExplorer(nightly 전용) 없이
         "다음에 조사해야 하는 것" 섹션에 적어둔 _Angle/_Direction 계열
         필드를 찾기 위한 용도입니다. 스냅샷 A/B 비교 기능도 있습니다.

      이 두 기능 다 "정답"을 찾아주는 게 아니라 후보를 좁히는 도구입니다.
      실제 회전을 Transform이 아니라 찾아낸 필드에 한 번만 써서 유지하는
      방식으로 바꾸는 건 필드를 특정한 다음 단계입니다.
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

    -- v2.4: 회전을 실제로 적용하는 훅 시점. HOOK_CANDIDATES 인덱스.
    hook_choice = 1,

    -- v2.4: 필드/메서드 탐색기 필터 키워드 (쉼표 구분)
    field_filter = "angle,direction,rotat,dir,yaw,target,action,motion,weapon,fsm",
    show_all_fields = false,
    field_explorer_open = false,
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

-- v2.4: 훅 타이밍을 게임 내에서 바로 바꿔볼 수 있도록 후보를 전부 등록해두고
-- cfg.hook_choice로 그중 하나만 활성화합니다. "잠깐 보였다가 원래 방향으로
-- 돌아가는" 증상이 LockScene 이후에 다른 단계가 다시 덮어써서 그런 건지
-- 확인하는 용도입니다.
local HOOK_CANDIDATES = {
    { label = "LockScene (post)",      name = "LockScene",      when = "post" },
    { label = "LockScene (pre)",       name = "LockScene",      when = "pre"  },
    { label = "UpdateMotion (post)",   name = "UpdateMotion",   when = "post" },
    { label = "UpdateMotion (pre)",    name = "UpdateMotion",   when = "pre"  },
    { label = "BeginRendering (post)", name = "BeginRendering", when = "post" },
}

local hook_labels = {}
for _, hc in ipairs(HOOK_CANDIDATES) do
    table.insert(hook_labels, hc.label)
end

for idx, hc in ipairs(HOOK_CANDIDATES) do
    local this_idx = idx

    local function handler()
        if cfg.hook_choice ~= this_idx then return end
        if last_apply_frame == frame_id then return end
        last_apply_frame = frame_id

        local ok, err = pcall(apply_locked_yaw)
        if not ok then
            last_error = "apply rotation: " .. tostring(err)
        end
    end

    if hc.when == "pre" then
        re.on_pre_application_entry(hc.name, handler)
    else
        re.on_application_entry(hc.name, handler)
    end
end

--==========================================================================
-- 11. 필드 / 메서드 탐색기 (실험용, v2.4)
--
--   PlayerBase 인스턴스의 실제 런타임 타입에서 시작해 부모 타입 체인을
--   걸어 올라가며 필드/메서드 이름을 모읍니다. ObjectExplorer가 GUI로
--   보여주는 것과 같은 정보를 스크립트 안에서 직접 뽑아, "다음에 조사해야
--   하는 것" 목록(각도/방향/액션/모션/무기/FSM 관련 필드)을 오버레이에서
--   바로 필터링해 볼 수 있게 합니다.
--==========================================================================

local function get_type_chain(td)
    local chain = {}
    local cur = td
    local guard = 0
    while cur and guard < 12 do
        table.insert(chain, cur)
        local ok, parent = pcall(function() return cur:get_parent_type() end)
        if not ok or not parent then break end
        cur = parent
        guard = guard + 1
    end
    return chain
end

local function format_field_value(v)
    if v == nil then return "nil" end
    local t = type(v)

    if t == "number" then
        return string.format("%.4f", v)
    end
    if t == "boolean" or t == "string" then
        return tostring(v)
    end

    if t == "table" or t == "userdata" then
        local ok_x, x = pcall(function() return v.x end)
        local ok_y, y = pcall(function() return v.y end)
        if ok_x and x ~= nil and ok_y and y ~= nil then
            local ok_z, z = pcall(function() return v.z end)
            local ok_w, w = pcall(function() return v.w end)
            if ok_w and w ~= nil then
                return string.format("(w=%.3f x=%.3f y=%.3f z=%.3f)", w, x, y, (ok_z and z) or 0.0)
            elseif ok_z and z ~= nil then
                return string.format("(x=%.3f y=%.3f z=%.3f)", x, y, z)
            else
                return string.format("(x=%.3f y=%.3f)", x, y)
            end
        end

        local ok_td, td = pcall(function() return v:get_type_definition() end)
        if ok_td and td then
            local ok_name, name = pcall(function() return td:get_full_name() end)
            if ok_name then return "<obj:" .. tostring(name) .. ">" end
        end
        return "<table/userdata>"
    end

    return tostring(v)
end

local function keyword_match(name)
    if cfg.show_all_fields then return true end
    local lname = name:lower()
    for kw in tostring(cfg.field_filter or ""):gmatch("[^,]+") do
        kw = kw:gsub("^%s+", ""):gsub("%s+$", "")
        if kw ~= "" and lname:find(kw, 1, true) then
            return true
        end
    end
    return false
end

-- name -> {name=field def, ...} 매칭되는 인스턴스 필드만 수집
local function collect_matching_fields(obj)
    local out = {}
    local ok_td, td = pcall(function() return obj:get_type_definition() end)
    if not ok_td or not td then return out end

    local seen = {}
    for _, t in ipairs(get_type_chain(td)) do
        local ok_fields, fields = pcall(function() return t:get_fields() end)
        if ok_fields and fields then
            for _, f in ipairs(fields) do
                local ok_static, is_static = pcall(function() return f:is_static() end)
                local ok_name, name = pcall(function() return f:get_name() end)
                if ok_static and not is_static and ok_name and name and not seen[name] and keyword_match(name) then
                    seen[name] = true
                    table.insert(out, { name = name, field = f })
                end
            end
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function collect_matching_methods(obj)
    local out = {}
    local ok_td, td = pcall(function() return obj:get_type_definition() end)
    if not ok_td or not td then return out end

    local seen = {}
    for _, t in ipairs(get_type_chain(td)) do
        local ok_methods, methods = pcall(function() return t:get_methods() end)
        if ok_methods and methods then
            for _, m in ipairs(methods) do
                local ok_name, name = pcall(function() return m:get_name() end)
                if ok_name and name and not seen[name] and keyword_match(name) then
                    seen[name] = true

                    local ok_pn, pnames = pcall(function() return m:get_param_names() end)
                    local args_str
                    if ok_pn and pnames and #pnames > 0 then
                        args_str = table.concat(pnames, ", ")
                    else
                        local ok_pc, pc = pcall(function() return m:get_num_params() end)
                        args_str = ok_pc and (tostring(pc) .. "개 인자") or "?"
                    end

                    table.insert(out, name .. "(" .. args_str .. ")")
                end
            end
        end
    end

    table.sort(out)
    return out
end

local field_dump_lines = {}
local field_dump_timer = 0.0
local method_dump_lines = {}

local function refresh_field_dump()
    field_dump_lines = {}
    local player = get_player()
    if not player then
        table.insert(field_dump_lines, "(player 없음)")
        return
    end

    local ok, fields = pcall(collect_matching_fields, player)
    if not ok or not fields then
        table.insert(field_dump_lines, "(필드 수집 실패: " .. tostring(fields) .. ")")
        return
    end

    for _, entry in ipairs(fields) do
        local ok_val, val = pcall(function() return entry.field:get_data(player) end)
        local shown = ok_val and format_field_value(val) or "<err>"
        table.insert(field_dump_lines, entry.name .. " = " .. shown)
    end
end

local function refresh_method_dump()
    method_dump_lines = {}
    local player = get_player()
    if not player then
        table.insert(method_dump_lines, "(player 없음)")
        return
    end

    local ok, methods = pcall(collect_matching_methods, player)
    if ok and methods then
        method_dump_lines = methods
    else
        table.insert(method_dump_lines, "(메서드 수집 실패)")
    end
end

-- 스냅샷 A/B 비교: 필드명 -> 문자열값
local snapshot_a, snapshot_b = {}, {}

local function capture_field_snapshot()
    local snap = {}
    local player = get_player()
    if player then
        local ok, fields = pcall(collect_matching_fields, player)
        if ok and fields then
            for _, entry in ipairs(fields) do
                local ok_val, val = pcall(function() return entry.field:get_data(player) end)
                snap[entry.name] = ok_val and format_field_value(val) or "<err>"
            end
        end
    end
    return snap
end

local function diff_snapshots()
    local diffs = {}
    for name, va in pairs(snapshot_a) do
        local vb = snapshot_b[name]
        if vb ~= nil and vb ~= va then
            table.insert(diffs, name .. "   A=" .. va .. "   B=" .. vb)
        end
    end
    table.sort(diffs)
    return diffs
end

re.on_frame(function()
    if cfg.field_explorer_open then
        field_dump_timer = field_dump_timer + get_delta_time()
        if field_dump_timer > 0.25 then
            field_dump_timer = 0.0
            local ok = pcall(refresh_field_dump)
            if not ok then
                field_dump_lines = { "(갱신 중 오류 발생)" }
            end
        end
    end
end)

--==========================================================================
--==========================================================================
-- 12. UI
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

    changed, val = imgui.combo("회전 적용 시점(실험)", cfg.hook_choice, hook_labels)
    if changed then cfg.hook_choice = val; save_cfg() end

    if cfg.debug then
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))
        imgui.text("correction active: " .. tostring(attack_correction_active))
        imgui.text("window remaining: " .. string.format("%.3f", attack_window_remaining) .. " sec")
        imgui.text("apply_rotation: " .. tostring(cfg.apply_rotation))
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.separator()
    if imgui.tree_node("필드 / 메서드 탐색기 (실험용)") then
        cfg.field_explorer_open = true

        changed, val = imgui.checkbox("전체 필드 보기 (필터 무시)", cfg.show_all_fields)
        if changed then cfg.show_all_fields = val; save_cfg() end

        changed, val = imgui.input_text("필터 키워드(쉼표구분)", cfg.field_filter)
        if changed then cfg.field_filter = val; save_cfg() end

        if imgui.button("필드 새로고침") then
            local ok = pcall(refresh_field_dump)
            if not ok then field_dump_lines = { "(갱신 중 오류 발생)" } end
        end
        imgui.same_line()
        if imgui.button("메서드 목록 보기") then
            local ok = pcall(refresh_method_dump)
            if not ok then method_dump_lines = { "(갱신 중 오류 발생)" } end
        end

        imgui.text(string.format("필드 %d개 표시 중 (0.25초마다 자동 갱신)", #field_dump_lines))
        for _, line in ipairs(field_dump_lines) do
            imgui.text(line)
        end

        if #method_dump_lines > 0 then
            imgui.separator()
            imgui.text(string.format("메서드 %d개", #method_dump_lines))
            for _, line in ipairs(method_dump_lines) do
                imgui.text(line)
            end
        end

        imgui.separator()
        imgui.text("스냅샷 비교 — 예: A = 공격 전(정지) / B = 보정 중이거나 되돌아간 직후")
        if imgui.button("스냅샷 A 저장") then snapshot_a = capture_field_snapshot() end
        imgui.same_line()
        if imgui.button("스냅샷 B 저장") then snapshot_b = capture_field_snapshot() end

        local diffs = diff_snapshots()
        imgui.text(string.format("A/B 값이 다른 필드: %d개", #diffs))
        for _, line in ipairs(diffs) do
            imgui.text(line)
        end

        imgui.tree_pop()
    else
        cfg.field_explorer_open = false
    end

    imgui.tree_pop()
end)

log.info(
    "[ModFocusRise v2.4] loaded. window=" ..
    tostring(cfg.correction_window_seconds) .. " sec, key=" .. tostring(key_display_name())
)
