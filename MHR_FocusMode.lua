--[[
    MHR_FocusMode v4.3.1 - Monster Hunter Rise (REFramework)용 "집중 조준" 모드

    무엇을 하는 스크립트인가:
      집중모드 버튼을 누르고 있는 동안(또는 토글로 켠 동안) 캐릭터가 카메라가
      보는 방향을 바라보도록 매 프레임 회전을 강제합니다.

    동작 우선순위 (매 프레임, 위에서부터 먼저 해당하는 조건 하나만 적용됨):
      1) 키/버튼 바인딩 캡처 중        -> 회전 적용 없음, 캡처만 진행
      2) 모드 꺼짐 (cfg.enabled=false) -> 회전 적용 없음
      3) 회피 버튼을 방금 누른 순간     -> 회전 적용을 즉시 멈추고 일시정지 타이머 시작
      4) 회피 일시정지 타이머가 남음    -> 계속 회전 미적용 (HUD는 계속 표시)
      5) 집중모드 버튼이 꺼져 있음      -> 회전 미적용
      6) 공격 방향 고정(attack lock) 중 -> 공격 시작 시점의 방향으로 강제 고정
      7) 공격 직후 handoff 구간        -> 고정을 풀고 현재 카메라 방향으로 자연스럽게 이어받음
      8) 그 외 평상시                  -> Activity Gate를 통과할 때만 카메라 방향을 따라감

    무기 자동 판별:
      player:get_type_definition():get_name()으로 얻은 타입 이름 문자열 하나만으로
      11종 무기를 매칭하고, 매칭에 실패하면 Generic(기본) Timing을 사용합니다.
      (다른 무기 객체 탐색, 부모 타입 탐색, 수동 무기 선택은 사용하지 않음)

    회전을 실제로 "적용"하는 시점:
      LockScene 전/후 + PrepareRendering 전/후, 총 4곳에서 매번 다시 적용합니다.
      게임이 한 프레임 안에서도 여러 단계에 걸쳐 캐릭터 방향을 자체적으로
      다시 쓰기 때문에, 한 번만 적용하면 중간에 덮어써져 버립니다.

    v4.3.x에서 생긴 것 (이 파일에도 그대로 있음):
      - 크로스헤어 색상을 Outline(테두리)/Fill(안쪽) 각각 HSB로 조절 가능.
        변환은 색상이 바뀔 때만 계산해서 캐시해 두고(1b, 9번 섹션),
        매 프레임 다시 계산하지 않습니다.
      - 설정 저장(save_cfg)이 실패해도 스크립트가 멈추지 않도록 pcall로
        보호하고, 실패 시 디버그 패널에 오류를 표시합니다(1번 섹션).

    이 파일(KR)과 직전 EN 파일의 차이:
      로직/구조 변경은 전혀 없고, REFramework 메뉴에 표시되는 UI 라벨
      문자열만 영어에서 한국어로 되돌아갔습니다(10. UI 섹션).

    설정 파일: ModFocusRise.json (UI에서 값을 바꾸면 자동 저장됩니다)

    컨트롤러 버튼 조회 관련 주의:
      via.hid.GamePad의 get_LastInputDevice -> isDown 조합은 REFramework가
      공식적으로 문서화하지 않은 API라서, 게임/REFramework 버전에 따라
      동작하지 않을 수 있습니다. 문제가 있으면 디버그 표시를 켜고
      "pad error" 항목에 나오는 문구를 확인하세요.

    섹션 안내:
      1.  설정              - 기본값, 설정 파일 로드/저장
      1b. 색상 유틸리티      - HSB -> ABGR 변환 (크로스헤어 색상용)
      2.  무기 Timing        - 무기별 표시 이름과 방향 고정 시간
      3.  키보드 입력        - 개별 키 상태 조회, 키 바인딩 캡처
      3b. 게임패드 입력      - 컨트롤러 버튼 상태 조회, 버튼 바인딩 캡처
      4.  마우스 입력        - 좌/우클릭, 컨트롤러 공격 버튼, 회피 입력 감지
      5.  Player/Camera/무기감지 - 트랜스폼 조회, 무기 자동 판별
      6.  수학 / 상태        - 쿼터니언<->yaw 변환, 공격 고정/handoff 상태값
      6b. Activity Gate     - "가만히 서 있으면 평상시 추적 안 함" 판정
      6c. 입력 통합          - KBM/컨트롤러 중 현재 장치에 맞는 집중모드 버튼 판정
      7.  입력/상태 업데이트 - 매 프레임 상태 갱신 (위 "동작 우선순위" 그대로 구현)
      8.  APPLY             - 실제로 캐릭터 회전을 적용하는 함수 + 4개 후크
      9.  HUD               - 화면 중앙 조준경 그리기 (Outline/Fill 색상 포함)
      10. UI                - REFramework 메뉴의 설정 화면
      11. 로드 완료 로그

    이전 버전들의 변경 이력은 파일 맨 아래를 참고하세요.
--]]

--==========================================================================
-- 1. 설정 (Config)
--==========================================================================
-- 설정 값을 저장하는 json 파일 경로.
-- UI에서 값을 바꾸면 save_cfg()가 이 파일에 바로 다시 씁니다.
local CFG_PATH = "ModFocusRise.json"

-- 이 스크립트가 실제로 사용하는 모든 설정값의 기본값 테이블입니다.
-- 아래에서, 저장된 설정(cfg)에 없는 키만 이 값으로 채워 넣습니다.
local DEFAULTS = {
    -- 집중모드 전체 켜짐/꺼짐. false면 이 아래 모든 로직이 동작을 멈춥니다.
    enabled        = true,
    -- 1 = 홀드(버튼을 누르고 있는 동안만 켜짐), 2 = 토글(눌러서 켜고, 다시 눌러서 끔).
    mode           = 1,
    -- 집중모드 키의 가상 키코드 값. 실제 판정에는 쓰이지 않고 저장만 되며,
    -- 판정은 바로 아래 key_name(문자열)으로 이루어집니다. 이전 버전 설정 파일과의
    -- 호환을 위해 남아있는 것으로 보이는, 이 스크립트에서는 읽지 않는 값입니다.
    key            = 0xA4,
    -- 실제 키 판정에 쓰이는 값. "Menu"는 REFramework 기준 좌측 Alt(LALT) 키를 의미합니다.
    key_name       = "Menu",

    -- 입력 장치 선택. 1 = 키보드+마우스(KBM), 2 = 컨트롤러.
    input_device   = 1,

    -- 회피 버튼 기본 바인딩. KBM은 Space, 컨트롤러는 RDown이 기본값이며 두 장치는
    -- 서로 다른 값으로 독립 저장됩니다. 사용자가 이미 다른 값으로 바꿔둔 경우
    -- 이 기본값으로 되돌리지 않습니다.
    evade_key_name = "Space",
    pad_evade_name = "RDown",

    -- 컨트롤러 버튼 바인딩 3종. 값은 via.hid.GamePadButton의 필드 이름 문자열이며,
    -- 빈 문자열("")이면 아직 바인딩되지 않은 상태입니다.
    --   - pad_key_name  : 집중모드 버튼 (KBM의 focus 키에 대응)
    --   - pad_atk1_name : 공격1 버튼 (좌클릭에 대응)
    --   - pad_atk2_name : 공격2 버튼 (우클릭에 대응)
    pad_key_name   = "LTrigBottom",
    pad_atk1_name  = "RUp",
    pad_atk2_name  = "RRight",

    -- 회피 버튼을 누른 순간부터 집중모드 회전 적용을 멈추는 시간(초).
    evade_focus_suspend_seconds = 0.700,

    -- smooth     : 평상시 카메라 추적 시 회전이 목표 방향을 따라가는 부드러움 정도.
    --              0에 가까울수록 즉시 반응, 1에 가까울수록 느리게 따라갑니다.
    -- yaw_offset : 계산된 목표 방향(yaw)에 더하는 보정값(라디안). 기본 0.
    smooth         = 0.35,
    yaw_offset     = 0.0,

    -- debug          : true면 UI 하단에 상태값(내부 변수)들을 표시합니다.
    -- show_reticle   : true면 집중모드 중 화면 중앙에 조준경 HUD를 표시합니다.
    -- apply_rotation : false면 회전 계산은 하되 실제로 캐릭터에 적용하지 않습니다
    --                  (내부 안전장치 성격의 마스터 스위치).
    debug          = false,
    show_reticle   = true,
    apply_rotation = true,

    -- 새로 추가: 크로스헤어 색상(HSB: 색상 0~360, 채도 0~100, 명도 0~100)입니다.
    -- 기본값은 검정 Outline(테두리) + 흰색 Fill(안쪽)이며, HSB -> 실제 색상 변환은
    -- 1b 섹션의 hsb_to_abgr()가 담당합니다. UI에서 슬라이더로 조절할 수 있습니다.
    reticle_outline_h = 0.0,
    reticle_outline_s = 0.0,
    reticle_outline_b = 0.0,
    reticle_fill_h    = 0.0,
    reticle_fill_s    = 0.0,
    reticle_fill_b    = 100.0,

    -- 무기 Timing은 항상 자동 인식되며, 무기를 인식하지 못했을 때만
    -- 이 Generic 값을 공격 방향 고정 시간으로 사용합니다.
    generic_window_seconds = 0.196,

    -- 무기별 고정 시간에 더해지는 소폭의 여유 시간(초). 공격 모션 중 카메라가
    -- 원래 방향으로 되돌아가려는 프레임을 줄이기 위한 값이며, UI에는 노출하지 않습니다.
    attack_lock_extension_seconds = 0.040,

    -- 공격 방향 고정이 끝난 뒤, 평상시 추적으로 넘어가기 전까지 현재 카메라
    -- 방향을 그대로 이어받는(handoff) 시간(초). 고정과 평상시 추적 사이에
    -- 방향이 잠깐 튀는 1프레임짜리 공백을 막기 위한 값입니다.
    attack_handoff_seconds = 0.100,

    -- 좌/우클릭(또는 컨트롤러 공격 버튼)을 이 시간 이상 누르고 있으면
    -- "홀드 공격"으로 판정합니다. 홀드 공격은 버튼을 떼는 즉시 방향 고정이 풀리며,
    -- 이 값은 무기별 Timing과는 무관한 공통 판정 기준입니다.
    attack_hold_threshold_seconds = 0.080,

    -- v1.8에서 가져온 "정지 판정" 기능. 평상시 카메라 추적에만 적용되며
    -- 공격 고정/handoff 동작에는 영향을 주지 않습니다.
    --   - activity_gate           : true면 캐릭터가 멈춰 있을 때는 카메라 방향을
    --                               따라가지 않습니다.
    --   - activity_pos_threshold  : 이동으로 인정할 프레임당 위치 변화량(미터).
    --   - activity_yaw_threshold  : 회전으로 인정할 프레임당 각도 변화량(라디안).
    --   - activity_hold_frames    : 움직임이 멈춘 뒤에도 추적을 유지할 프레임 수.
    activity_gate           = true,
    activity_pos_threshold  = 0.01,
    activity_yaw_threshold  = 0.015,
    activity_hold_frames    = 12,
}

-- 저장된 설정 파일을 불러오고, 파일에 없는 키는 DEFAULTS 값으로 채웁니다.
local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

-- 컨트롤러 바인딩 3종은 값이 비어 있을 때만 기본값을 채웁니다.
-- 사용자가 이미 다른 버튼으로 바꿔둔 값은 그대로 유지합니다.
if cfg.pad_key_name == nil or cfg.pad_key_name == "" then
    cfg.pad_key_name = DEFAULTS.pad_key_name
end
if cfg.pad_atk1_name == nil or cfg.pad_atk1_name == "" then
    cfg.pad_atk1_name = DEFAULTS.pad_atk1_name
end
if cfg.pad_atk2_name == nil or cfg.pad_atk2_name == "" then
    cfg.pad_atk2_name = DEFAULTS.pad_atk2_name
end

-- 새로 추가된 상태값: 가장 최근 설정 저장이 실패했을 때의 오류 메시지(디버그 표시용). 저장에
-- 성공하면 nil로 초기화됩니다.
local cfg_save_error = nil

-- cfg 테이블 전체를 그대로 설정 파일에 씁니다.
local function save_cfg()
    -- 설정 파일 쓰기가 실패할 수 있어(디스크 오류 등) pcall로 감쌉니다. 이전 버전에는 이 보호
    -- 장치가 없었습니다.
    local ok, err = pcall(function()
        json.dump_file(CFG_PATH, cfg)
    end)

    -- 저장에 실패하면 오류 메시지를 cfg_save_error에 남기고 false를 반환합니다.
    if not ok then
        cfg_save_error = tostring(err)
        return false
    end

    -- 저장에 성공하면 이전 오류를 지우고 true를 반환합니다. 반환값은 필요한 호출부에서 성공 여부를
    -- 확인하는 데 쓸 수 있습니다.
    cfg_save_error = nil
    return true
end

--==========================================================================
-- 1b. 색상 유틸리티 (HSB -> ABGR)
--==========================================================================
-- 값을 [min_value, max_value] 범위로 잘라냅니다. 아래 HSB -> 색상 변환에서 반복적으로 사용됩니다.
local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

-- HSB(색상/채도/명도) 값을 REFramework의 draw/imgui가 요구하는 0xAABBGGRR
-- 정수 색상(ABGR)으로 변환합니다. 표준 HSV -> RGB 변환 공식을 그대로 쓰고,
-- 마지막에 채널 순서만 ABGR로 맞춰 반환합니다. 알파(A)는 항상 불투명(0xFF)입니다.
local function hsb_to_abgr(h, s, b)
    h = (tonumber(h) or 0.0) % 360.0
    s = clamp((tonumber(s) or 0.0) / 100.0, 0.0, 1.0)
    b = clamp((tonumber(b) or 0.0) / 100.0, 0.0, 1.0)

    local c = b * s
    local hp = h / 60.0
    local x = c * (1.0 - math.abs((hp % 2.0) - 1.0))

    local r1, g1, b1 = 0.0, 0.0, 0.0
    if hp < 1.0 then
        r1, g1, b1 = c, x, 0.0
    elseif hp < 2.0 then
        r1, g1, b1 = x, c, 0.0
    elseif hp < 3.0 then
        r1, g1, b1 = 0.0, c, x
    elseif hp < 4.0 then
        r1, g1, b1 = 0.0, x, c
    elseif hp < 5.0 then
        r1, g1, b1 = x, 0.0, c
    else
        r1, g1, b1 = c, 0.0, x
    end

    local m = b - c
    local r = math.floor(clamp(r1 + m, 0.0, 1.0) * 255.0 + 0.5)
    local g = math.floor(clamp(g1 + m, 0.0, 1.0) * 255.0 + 0.5)
    local blue = math.floor(clamp(b1 + m, 0.0, 1.0) * 255.0 + 0.5)

    return 0xFF000000 + blue * 0x10000 + g * 0x100 + r
end

--==========================================================================
-- 2. 무기 Timing
--==========================================================================
-- 아래 두 테이블은 같은 무기 키(GreatSword 등)를 공유합니다.
-- WEAPON_LABELS  : UI/디버그 표시에 쓰이는 한글 이름.
local WEAPON_LABELS = {
    GreatSword     = "대검",
    LongSword      = "태도",
    ChargeBlade    = "차지액스",
    SwordAndShield = "한손검",
    DualBlades     = "쌍검",
    Hammer         = "해머",
    HuntingHorn    = "수렵피리",
    Lance          = "랜스",
    Gunlance       = "건랜스",
    SwitchAxe      = "슬래시액스",
    InsectGlaive   = "조충곤",
    Generic        = "미감지/기본",
}

-- WEAPON_TIMINGS : 무기별 공격 방향 고정 시간(초). 아래 detect_weapon_key()가
--                  이 키들 중 하나로 무기를 판별하면 그 값을 그대로 사용합니다.
local WEAPON_TIMINGS = {
    GreatSword     = 0.24,
    LongSword      = 0.18,
    ChargeBlade    = 0.22,
    SwordAndShield = 0.16,
    DualBlades     = 0.14,
    Hammer         = 0.24,
    HuntingHorn    = 0.22,
    Lance          = 0.18,
    Gunlance       = 0.20,
    SwitchAxe      = 0.20,
    InsectGlaive   = 0.18,
}

--==========================================================================
-- 3. 키보드 입력
--==========================================================================
-- via.hid.Keyboard의 싱글턴/타입 정의는 최초 1회만 조회해서 캐시해 둡니다
-- (get_keyboard 안에서 비어 있을 때만 다시 조회).
local kb_singleton, kb_tdef, kb_key_tdef
-- key_prev_down  : 선언만 되고 값이 세팅될 뿐, 이 스크립트 안에서 읽는 곳은
--                  없는 값입니다(삭제해도 동작에는 영향 없음).
-- key_prev_evade : 회피 키의 "직전 프레임 눌림 상태". 아래 update_evade_input()에서
--                  "방금 눌린 순간"만 true로 잡아내는 데 사용합니다.
-- input_error    : 키보드 관련 오류 메시지를 담아 두는 곳(디버그 표시용).
local key_prev_down = false
local key_prev_evade = false
local input_error = nil

-- via.hid.Keyboard 싱글턴에서 실제 입력 장치(Device) 객체를 가져옵니다.
-- 싱글턴/타입 정의가 없으면(아직 준비되지 않음 등) nil을 반환합니다.
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

-- KeyboardKey enum에서 이름(name)에 해당하는 정수 키 값을 가져옵니다.
-- 필드 조회 자체가 실패할 수 있어 pcall로 감쌉니다.
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

-- "Menu"는 실제로는 LALT 키이므로, 화면에는 알아보기 쉬운 이름으로 바꿔 보여줍니다.
local function key_display_name()
    if cfg.key_name == "Menu" then return "LALT" end
    return tostring(cfg.key_name or "Menu")
end

-- 회피 키 이름도 위와 동일하게, 기본값 "Space"는 "SPACE"로 바꿔 표시합니다.
local function evade_key_display_name()
    if cfg.evade_key_name == "Space" then return "SPACE" end
    return tostring(cfg.evade_key_name or "Space")
end

-- cfg에 저장된 키 이름으로 실제 키 값을 가져오되, 실패하면 input_error에
-- 원인을 남깁니다(디버그 표시용).
local function get_bound_key_value(name)
    local key_name = name or cfg.key_name or "Menu"
    local v = get_key_value(key_name)
    if v == nil then
        input_error = "KeyboardKey not found: " .. tostring(key_name)
    end
    return v
end

-- 주어진 이름의 키가 "지금 눌려 있는지" 여부를 반환합니다. isDown 호출도 pcall로 보호합니다.
local function key_down_for(name)
    local d = get_keyboard()
    if not d then return false end

    local key = get_bound_key_value(name)
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

-- 현재 설정된 집중모드 키가 눌려 있는지 여부.
local function key_down()
    return key_down_for(cfg.key_name or "Menu")
end

-- "버튼 변경" 모드일 때 사용됩니다. KeyboardKey의 모든 정적(static) 필드를
-- 순회하면서 지금 눌려 있는 키를 찾아 cfg[cfg_field]에 저장합니다.
-- Escape 키 자체는 바인딩 대상에서 제외합니다(취소 용도로 남겨둠).
-- 반환값: true면 캡처 완료(성공 또는 이번 프레임엔 대상 없음), false면 계속 대기.
local function capture_keyboard_binding(cfg_field)
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
                        cfg[cfg_field] = name
                        if cfg_field == "key_name" then
                            cfg.key = value
                        end
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

-- 집중모드 키 바인딩 캡처(위 함수를 key_name 대상으로 호출).
local function capture_key()
    return capture_keyboard_binding("key_name")
end

-- 바인딩 캡처를 취소하는 공용 키(ESC). 키보드/컨트롤러 바인딩 캡처 중
-- 공통으로 쓰이므로 한 곳에만 정의합니다.
local function escape_pressed()
    local d = get_keyboard()
    if not d then return false end

    local esc = get_key_value("Escape")
    if esc == nil then return false end

    local ok, down = pcall(function()
        return d:call("isDown", esc) == true
    end)

    return ok and down == true
end

--==========================================================================
-- 3b. 게임패드(컨트롤러) 입력
--==========================================================================
-- via.hid.GamePad 싱글턴/타입 정의도 키보드와 마찬가지로 최초 1회만 캐시합니다.
local pad_singleton, pad_tdef, pad_button_tdef
-- pad_prev_atk1/atk2/evade : 각 컨트롤러 버튼의 "직전 프레임 눌림 상태".
--                             버튼을 "방금 누른 순간"만 감지하기 위해 사용합니다.
-- pad_error                 : 컨트롤러 관련 오류 메시지(디버그 표시용).
local pad_prev_atk1 = false
local pad_prev_atk2 = false
local pad_prev_evade = false
local pad_error = nil

-- 현재 입력에 사용 중인 컨트롤러 디바이스를 가져옵니다.
-- get_LastInputDevice는 REFramework가 공식 문서화하지 않은 API라서
-- 호출 자체가 실패할 수 있어 pcall로 감쌉니다.
local function get_gamepad()
    if not pad_singleton then
        pad_singleton   = sdk.get_native_singleton("via.hid.GamePad")
        pad_tdef        = sdk.find_type_definition("via.hid.GamePad")
        pad_button_tdef = sdk.find_type_definition("via.hid.GamePadButton")
    end

    if not pad_singleton or not pad_tdef then
        return nil
    end

    local ok, device = pcall(function()
        return sdk.call_native_func(pad_singleton, pad_tdef, "get_LastInputDevice")
    end)

    if not ok then
        pad_error = "get_LastInputDevice: " .. tostring(device)
        return nil
    end

    return device
end

-- GamePadButton enum에서 이름에 해당하는 버튼 값을 가져옵니다(키보드 쪽과 동일한 패턴).
local function get_pad_button_value(name)
    if not pad_button_tdef or not name or name == "" then return nil end

    local field = pad_button_tdef:get_field(name)
    if not field then
        pad_error = "GamePadButton not found: " .. tostring(name)
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)

    if not ok then
        pad_error = "GamePadButton get_data: " .. tostring(value)
        return nil
    end

    return value
end

-- 주어진 이름의 컨트롤러 버튼이 지금 눌려 있는지 여부.
local function pad_down(name)
    local d = get_gamepad()
    if not d then return false end

    local button = get_pad_button_value(name)
    if button == nil then return false end

    local ok, result = pcall(function()
        return d:call("isDown", button) == true
    end)

    if not ok then
        pad_error = "pad isDown: " .. tostring(result)
        return false
    end

    return result
end

-- REFramework 내부 버튼 이름(RUp, LTrigBottom 등)을 플레이스테이션/엑스박스
-- 표기(△/Y, L2/LT 등)로 바꿔서 UI에 보여주기 위한 표입니다.
-- 입력 판정이나 저장값 자체는 바꾸지 않고 화면 표시만 바꿉니다.
local function pad_display_name(name)
    if not name or name == "" then
        return ""
    end

    local labels = {
        -- 얼굴 버튼(면 버튼).
        RUp          = "△ / Y",
        RRight       = "○ / B",
        RDown        = "× / A",
        RLeft        = "□ / X",

        -- 게임 안에서 자주 쓰이는 논리적 별칭(확인/취소).
        Decide       = "× / A",
        Cancel       = "○ / B",

        -- 방향패드(D-pad).
        LUp          = "D-pad ↑",
        LDown        = "D-pad ↓",
        LLeft        = "D-pad ←",
        LRight       = "D-pad →",

        -- 왼쪽/오른쪽 스틱을 방향키처럼 다룰 때의 이름.
        EmuLup       = "Left Stick ↑",
        EmuLdown     = "Left Stick ↓",
        EmuLleft     = "Left Stick ←",
        EmuLright    = "Left Stick →",
        EmuRup       = "Right Stick ↑",
        EmuRdown     = "Right Stick ↓",
        EmuRleft     = "Right Stick ←",
        EmuRright    = "Right Stick →",

        -- 범퍼/트리거.
        LTrigTop     = "L1 / LB",
        LTrigBottom  = "L2 / LT",
        RTrigTop     = "R1 / RB",
        RTrigBottom  = "R2 / RT",

        -- 스틱 누르기(클릭).
        LStickPush   = "L3 / LS",
        RStickPush   = "R3 / RS",
    }

    return labels[name] or tostring(name)
end

-- 컨트롤러 버튼 바인딩 캡처. 키보드 캡처(capture_keyboard_binding)와 같은
-- 역할이지만 대상이 GamePadButton이라는 점이 다릅니다.
--   - 키보드 ESC를 누르면 저장하지 않고 캡처만 종료합니다.
--   - None/Any/All처럼 "묶음"을 의미하는 필드는 실제 버튼이 아니므로 건너뜁니다.
-- 반환값: true면 캡처 종료(저장 또는 취소), false면 계속 대기.
local function capture_pad_button(cfg_field)
    if escape_pressed() then
        return true
    end

    local d = get_gamepad()
    if not d or not pad_button_tdef then return false end

    for _, field in ipairs(pad_button_tdef:get_fields()) do
        if field:is_static() then
            local name = field:get_name()

            local ok_value, value = pcall(function()
                return field:get_data(nil)
            end)

            if ok_value and value ~= nil and value ~= 0 then
                local lname = string.lower(name)
                if lname ~= "none" and lname ~= "any" and lname ~= "all" then
                    local ok_down, down = pcall(function()
                        return d:call("isDown", value) == true
                    end)

                    if ok_down and down then
                        cfg[cfg_field] = name
                        save_cfg()
                        return true
                    end
                end
            end
        end
    end

    return false
end

--==========================================================================
-- 4. 마우스 입력
--==========================================================================
-- via.hid.Mouse 싱글턴/타입 정의도 동일하게 최초 1회만 캐시합니다.
local mouse_singleton, mouse_tdef, mouse_button_tdef
-- mouse_prev_l/r : 좌/우클릭 각각의 "직전 프레임 눌림 상태".
local mouse_prev_l = false
local mouse_prev_r = false
-- attack_held는 이 섹션(마우스)과 3b 섹션(패드) 양쪽에서 공유하는 전역
-- 상태이며, 아래 update_attack_input()/update_pad_attack_input() 중 이번
-- 프레임에 실제로 호출된 쪽이 이 값을 갱신합니다.
local attack_held = false
local mouse_error = nil

-- via.hid.Mouse 싱글턴에서 실제 입력 장치 객체를 가져옵니다.
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

-- MouseButton enum에서 이름에 해당하는 버튼 값을 가져옵니다.
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

-- 주어진 이름(L 또는 R)의 마우스 버튼이 지금 눌려 있는지 여부.
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

-- KBM 모드에서 매 프레임 호출됩니다. 좌/우클릭 각각의 "방금 눌린 순간"을
-- 감지해서 트리거로 반환하고, attack_held(누르고 있는 중)도 함께 갱신합니다.
local function update_attack_input()
    local l = mouse_down("L")
    local r = mouse_down("R")

    local trg_l = l and not mouse_prev_l
    local trg_r = r and not mouse_prev_r

    mouse_prev_l = l
    mouse_prev_r = r
    attack_held  = l or r

    return trg_l or trg_r
end

-- 컨트롤러 모드에서 매 프레임 호출됩니다. 위 update_attack_input()과 같은
-- 구조이며 대상만 컨트롤러의 공격1/공격2 버튼으로 바뀝니다. 이렇게 만들어진
-- 트리거는 마우스 좌/우클릭과 완전히 동일하게 취급되어, 탭/홀드 판정과
-- 무기별 방향 고정, handoff 로직을 그대로 공유합니다.
local function update_pad_attack_input()
    local a1 = pad_down(cfg.pad_atk1_name)
    local a2 = pad_down(cfg.pad_atk2_name)

    local trg1 = a1 and not pad_prev_atk1
    local trg2 = a2 and not pad_prev_atk2

    pad_prev_atk1 = a1
    pad_prev_atk2 = a2
    attack_held   = a1 or a2

    return trg1 or trg2
end

-- 회피 버튼의 "방금 눌린 순간"을 감지합니다. 집중모드 버튼과는 완전히
-- 독립적으로 매 프레임 감지하며, 현재 장치(패드 또는 키보드)만 확인합니다.
local function update_evade_input()
    if cfg.input_device == 2 then
        local now = pad_down(cfg.pad_evade_name)
        local trg = now and not pad_prev_evade
        pad_prev_evade = now
        return trg
    end

    local now = key_down_for(cfg.evade_key_name or "Space")
    local trg = now and not key_prev_evade
    key_prev_evade = now
    return trg
end

--==========================================================================
-- 5. Player / Camera / 무기(BFM Type) 감지
--==========================================================================
-- 현재 조작 중인 플레이어 객체를 가져옵니다. 정상 경로(getPlayer(0))가
-- 실패하면 findMasterPlayer()로 한 번 더 시도합니다.
local function get_player()
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end

    local ok, player = pcall(function()
        return pm:call("getPlayer", 0)
    end)

    if ok and player then
        return player
    end

    local ok_fallback, master = pcall(function()
        return pm:call("findMasterPlayer")
    end)

    if ok_fallback then
        return master
    end

    return nil
end

-- 게임 오브젝트(Player, Camera 등)에서 위치/회전을 다루는 Transform 컴포넌트를 꺼냅니다.
local function get_transform(obj)
    if not obj then return nil end

    local go = obj:call("get_GameObject")
    if not go then return nil end

    return go:call("get_Transform")
end

-- via.SceneManager 싱글턴/타입 정의를 캐시해 두고, 카메라의 Transform을 가져오는 데 사용합니다.
local sm_singleton, sm_tdef

-- 현재 씬의 메인 뷰 -> 주 카메라(PrimaryCamera)를 따라가 카메라의 Transform을 가져옵니다.
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

-- 무기 자동 판별에 쓰이는 상태값들입니다.
--   - bfm_type_name          : 감지된 원본 타입 이름(디버그 표시용).
--   - current_weapon_key     : 판별된 무기 키(WEAPON_LABELS/WEAPON_TIMINGS의 키).
--   - current_window_seconds : 현재 무기에 적용할 방향 고정 시간(초).
local bfm_type_name = "(unknown)"
local current_weapon_key = "Generic"
local current_window_seconds = 0.196
local weapon_detect_error = nil

-- 무기 키마다 "타입 이름에 이 문자열들 중 하나라도 포함되어 있으면 이 무기로
-- 판정한다"는 매칭 패턴 목록입니다. 대소문자/특수문자는 아래 normalize_bfm_type()
-- 에서 미리 정리한 뒤 비교합니다.
local BFM_WEAPON_PATTERNS = {
    { key = "GreatSword",     patterns = { "GreatSword", "Greatsword" } },
    { key = "LongSword",      patterns = { "LongSword", "Longsword" } },
    { key = "ChargeBlade",    patterns = { "ChargeBlade", "Chargeblade", "ChargeAxe" } },
    { key = "SwordAndShield", patterns = { "SwordAndShield", "SwordShield", "ShortSword" } },
    { key = "DualBlades",     patterns = { "DualBlades", "DualBlade" } },
    { key = "Hammer",         patterns = { "Hammer" } },
    { key = "HuntingHorn",    patterns = { "HuntingHorn", "Horn" } },
    { key = "Lance",          patterns = { "Lance" } },
    { key = "Gunlance",       patterns = { "GunLance", "Gunlance" } },
    { key = "SwitchAxe",      patterns = { "SwitchAxe", "SlashAxe" } },
    { key = "InsectGlaive",   patterns = { "InsectGlaive", "Insect" } },
}

-- 비교를 쉽게 하기 위해 타입 이름을 소문자로 바꾸고 영문/숫자가 아닌 문자는 모두 제거합니다.
local function normalize_bfm_type(name)
    if not name then return "" end
    local s = tostring(name):lower()
    s = s:gsub("[^%w]", "")
    return s
end

-- 플레이어 객체의 타입 이름(get_type_definition():get_name())을 가져옵니다.
-- 이 문자열 하나가 무기 자동 판별의 유일한 근거입니다.
local function get_bfm_type_name(player)
    if not player then
        bfm_type_name = "(unknown)"
        return nil
    end

    local ok, name = pcall(function()
        local td = player:get_type_definition()
        if not td then return nil end
        return td:get_name()
    end)

    if not ok then
        bfm_type_name = "(error)"
        weapon_detect_error = tostring(name)
        return nil
    end

    bfm_type_name = name or "(unknown)"
    weapon_detect_error = nil
    return name
end

-- 정규화한 타입 이름을 BFM_WEAPON_PATTERNS의 각 패턴과 순서대로 비교해서
-- 가장 먼저 일치하는 무기 키를 반환합니다. 아무 것도 일치하지 않으면
-- "Generic"(미감지/기본)으로 처리합니다.
local function detect_weapon_key(player)
    local type_name = get_bfm_type_name(player)

    if not type_name then
        current_weapon_key = "Generic"
        return "Generic"
    end

    local normalized = normalize_bfm_type(type_name)

    for _, item in ipairs(BFM_WEAPON_PATTERNS) do
        for _, pattern in ipairs(item.patterns) do
            local p = normalize_bfm_type(pattern)
            if p ~= "" and string.find(normalized, p, 1, true) then
                current_weapon_key = item.key
                return item.key
            end
        end
    end

    current_weapon_key = "Generic"
    return "Generic"
end

-- detect_weapon_key()로 무기를 판별한 뒤, WEAPON_TIMINGS에서 그 무기의
-- 고정 시간을 찾아 current_window_seconds에 반영합니다. Generic이거나
-- 표에 없는 무기면 cfg.generic_window_seconds를 사용합니다.
local function update_weapon_profile(player)
    local key = detect_weapon_key(player)

    if key == "Generic" then
        current_window_seconds = cfg.generic_window_seconds
    else
        current_window_seconds = WEAPON_TIMINGS[key] or cfg.generic_window_seconds
    end

    return current_window_seconds
end

--==========================================================================
-- 6. 수학 / 상태
--==========================================================================
-- 쿼터니언 회전값에서 좌우 방향(yaw, y축 회전각)만 뽑아냅니다.
local function yaw_from_quat(q)
    return math.atan(
        2.0 * (q.w * q.y + q.x * q.z),
        1.0 - 2.0 * (q.y * q.y + q.x * q.x)
    )
end

-- yaw 각도(라디안) 하나만으로 쿼터니언 회전값을 만듭니다(위 함수의 역연산).
local function quat_from_yaw(yaw)
    local h = yaw * 0.5
    return Quaternion.new(
        math.cos(h),
        0.0,
        math.sin(h),
        0.0
    )
end

-- 각도를 -π ~ +π 범위로 정규화합니다. 359도와 1도처럼 실제로는 가까운 각도를 최단 경로로 비교하기
-- 위해 필요합니다.
local function wrap_pi(a)
    while a >  math.pi do a = a - math.pi * 2.0 end
    while a < -math.pi do a = a + math.pi * 2.0 end
    return a
end

-- 이 스크립트 전체에서 공유되는 핵심 상태 변수들입니다.
--   - focus_active : 집중모드가 지금 켜져 있는지(버튼을 누르고 있거나 토글 켬).
--   - toggle_state : 토글 모드(mode=2)에서 현재 켬/끔 상태.
local focus_active = false
local toggle_state = false

-- 바인딩 캡처 대상. nil(캡처 없음) / "kbm" / "kbm_evade" / "pad_focus" / "pad_evade" / "pad_atk1" /
-- "pad_atk2" 중 하나.
local binding_target = nil

-- 집중모드 버튼의 "직전 프레임 눌림 상태". 토글 모드에서 "방금 눌린 순간"만 감지하는 데
-- 사용합니다(장치와 무관한 공용 상태).
local focus_prev_down = false

-- 회피 입력 이후 회전 적용을 막는 남은 시간(초). 0보다 크면 "회피로 인한 일시정지 중"입니다.
local focus_suspend_remaining = 0.0

-- 공격 방향 고정 관련 상태입니다.
--   - attack_lock_active    : 지금 방향을 강제로 고정 중인지.
--   - attack_locked_yaw     : 고정된 목표 방향(yaw, 라디안).
--   - attack_lock_remaining : 고정을 유지할 남은 시간(초). 홀드 중에는 아래
--                             current_lock_floor() 밑으로 떨어지지 않게 붙잡아 둡니다.
local attack_lock_active = false
local attack_locked_yaw = nil
local attack_lock_remaining = 0.0

-- attack_hold_elapsed : 공격 버튼을 누르고 있는 시간(홀드/탭 구분용).
-- attack_is_hold       : attack_hold_elapsed가 threshold를 넘어 "홀드"로
--                        확정되었는지 여부.
local attack_hold_elapsed = 0.0
local attack_is_hold = false

-- 공격 고정이 끝난 뒤 카메라 방향을 이어받는 handoff 구간의 남은 시간(초).
local attack_handoff_remaining = 0.0

-- last_error       : 가장 최근에 발생한 예외 메시지(디버그 표시용).
-- apply_count      : 실제로 회전을 적용한 누적 횟수(디버그 표시용).
-- frame_id         : on_frame이 호출될 때마다 증가하는 프레임 카운터.
-- last_apply_frame : "평상시 추적"을 마지막으로 적용한 frame_id. 한 프레임에
--                    중복 적용되는 것을 막는 데 사용합니다(apply_normal_camera_now 참고).
local last_error = nil
local apply_count = 0
local frame_id = 0
local last_apply_frame = -1

local app_singleton, app_tdef

-- via.Application에서 프레임 간 경과 시간(초)을 가져옵니다. 값이 비정상
-- (0 이하이거나 0.25초 이상, 즉 4fps 미만)이면 60fps 기준 고정값으로 대체합니다.
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

-- 공격 방향 고정/handoff 관련 상태를 모두 초기값으로 되돌립니다.
local function reset_attack_lock()
    attack_lock_active = false
    attack_locked_yaw = nil
    attack_lock_remaining = 0.0
    attack_hold_elapsed = 0.0
    attack_is_hold = false
    attack_handoff_remaining = 0.0
end

-- 회피 입력이 들어온 순간 호출됩니다. 회전 일시정지 시간을 설정값만큼
-- 확보하고(이미 남은 시간이 더 길면 줄이지 않음), 회피 중에 공격 고정/handoff가
-- 다시 회전을 덮어쓰지 않도록 함께 초기화합니다.
local function start_focus_suspend()
    focus_suspend_remaining = math.max(
        focus_suspend_remaining,
        math.max(0.0, cfg.evade_focus_suspend_seconds or 0.700)
    )

    reset_attack_lock()
end

-- 회피로 인한 회전 일시정지 중인지 여부(HUD 표시와는 무관, 회전 적용 여부에만 사용).
local function focus_is_suspended()
    return focus_suspend_remaining > 0.0
end

-- 회피로 인한 회전 일시정지를 즉시 해제합니다.
local function reset_focus_suspend()
    focus_suspend_remaining = 0.0
end

-- 공격 고정이 끝났을 때 handoff 구간을 시작합니다(이미 남은 시간이 더 길면 줄이지 않음).
local function start_attack_handoff()
    attack_handoff_remaining = math.max(
        attack_handoff_remaining,
        math.max(0.0, cfg.attack_handoff_seconds or 0.0)
    )
end

-- 무기별 지정 시간에 내부 여유 시간(attack_lock_extension_seconds)을 더한
-- 값으로, 공격 버튼을 누르고 있는 동안 attack_lock_remaining이 이 밑으로
-- 떨어지지 않도록 붙잡아 두는 "최소 유지 시간"입니다.
local function current_lock_floor()
    return math.max(
        0.01,
        current_window_seconds +
        math.max(0.0, cfg.attack_lock_extension_seconds or 0.0)
    )
end

--==========================================================================
-- 6b. Activity Gate (v1.8 재사용) - "평상시 추적"에만 적용
--==========================================================================
-- 정지 여부 판정에 쓰이는 상태값들입니다. 공격 고정/handoff에는 영향을 주지
-- 않고, 아래 apply_normal_camera_now()의 "평상시 추적"에만 게이트로 쓰입니다.
--   - activity_active       : 지금 "움직이는 중"으로 판정되어 추적을 허용하는지.
--   - activity_frames_left  : 움직임이 멈춘 뒤에도 추적을 유지할 남은 프레임 수.
--   - activity_initialized  : 첫 프레임(비교 기준이 아직 없음) 여부.
--   - activity_last_pos/yaw : 다음 프레임과 비교하기 위한 직전 위치/방향.
local activity_active = false
local activity_frames_left = 0
local activity_initialized = false
local activity_last_pos = nil
local activity_last_yaw = nil

-- 벡터를 값으로 복사합니다(참조만 들고 있으면 다음 프레임에 원본이 바뀌어 비교가 틀어짐).
local function copy_vec3(v)
    return { x = v.x, y = v.y, z = v.z }
end

-- Activity Gate 관련 상태를 모두 초기화합니다(집중모드가 꺼지거나 회피 중일 때 등에 호출).
local function reset_activity()
    activity_active = false
    activity_frames_left = 0
    activity_initialized = false
    activity_last_pos = nil
    activity_last_yaw = nil
end

-- 매 프레임 호출되어 캐릭터가 "움직이는 중"인지 판정합니다.
--   - activity_gate가 꺼져 있으면 항상 움직이는 것으로 취급합니다.
--   - 위치 변화가 activity_pos_threshold 이상이거나, 회전 변화가
--     activity_yaw_threshold 이상이면 "움직임"으로 보고 activity_frames_left를
--     다시 채웁니다.
--   - 움직임이 없으면 activity_frames_left를 매 프레임 1씩 줄이고,
--     0보다 클 때만 activity_active = true로 유지합니다(관성 처리).
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
        local moved =
            (dx * dx + dy * dy + dz * dz) >=
            (cfg.activity_pos_threshold * cfg.activity_pos_threshold)

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

--==========================================================================
-- 6c. 입력 장치 통합 (집중모드 버튼)
--==========================================================================
-- cfg.input_device에 따라 집중모드 버튼을 컨트롤러 또는 키보드 중 하나로 조회합니다.
local function focus_button_down()
    if cfg.input_device == 2 then
        return pad_down(cfg.pad_key_name)
    end
    return key_down()
end

-- 집중모드 버튼이 "방금 눌린 순간"인지 여부(토글 모드에서만 사용).
local function focus_button_trg()
    local now = focus_button_down()
    local trg = now and not focus_prev_down
    focus_prev_down = now
    return trg
end

--==========================================================================
-- 7. 입력 / 상태 업데이트 (매 프레임)
--==========================================================================
-- 게임 루프에서 매 프레임 호출됩니다. 아래로 내려가면서 조건에 맞는 곳에서
-- return으로 빠져나가는 구조이며, 코드가 위에서부터 등장하는 순서가 곧
-- "이번 프레임에 무엇을 할지"를 결정하는 우선순위입니다.
re.on_frame(function()
    -- 프레임 카운터 증가. apply_normal_camera_now()에서 중복 적용 방지에 사용됩니다.
    frame_id = frame_id + 1

    -- [우선순위 1] 키/버튼 바인딩 캡처 중이면, 회전 적용 없이 캡처만 진행하고
    -- 이번 프레임을 끝냅니다(아래 return). 캡처 대상에 따라 해당하는 capture_*
    -- 함수를 호출하고, 캡처가 끝나면 그 버튼의 "직전 눌림" 상태를 리셋해서
    -- 캡처 종료 직후 그 버튼이 실수로 다시 트리거되지 않게 합니다.
    if binding_target then
        local done = false

        if binding_target == "kbm" then
            done = capture_key()
        elseif binding_target == "kbm_evade" then
            done = capture_keyboard_binding("evade_key_name")
            if done then key_prev_evade = false end
        elseif binding_target == "pad_focus" then
            done = capture_pad_button("pad_key_name")
            if done then focus_prev_down = false end
        elseif binding_target == "pad_evade" then
            done = capture_pad_button("pad_evade_name")
            if done then pad_prev_evade = false end
        elseif binding_target == "pad_atk1" then
            done = capture_pad_button("pad_atk1_name")
            if done then pad_prev_atk1 = false end
        elseif binding_target == "pad_atk2" then
            done = capture_pad_button("pad_atk2_name")
            if done then pad_prev_atk2 = false end
        else
            done = true
        end

        -- 캡처가 끝났으면(성공/취소 모두 포함) 바인딩 모드를 해제합니다.
        if done then
            binding_target = nil
        end

        -- 캡처 중에는 집중모드/공격고정/회피 일시정지/정지판정을 모두 안전하게 꺼둡니다.
        focus_active = false
        reset_attack_lock()
        reset_focus_suspend()
        key_prev_evade = false
        pad_prev_evade = false
        reset_activity()
        return
    end

    -- [우선순위 2] 모드 자체가 꺼져 있으면, 모든 입력 상태를 초기화하고
    -- 이번 프레임은 아무 회전도 적용하지 않습니다.
    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        mouse_prev_l = false
        mouse_prev_r = false
        focus_prev_down = false
        key_prev_evade = false
        pad_prev_atk1 = false
        pad_prev_atk2 = false
        pad_prev_evade = false
        reset_attack_lock()
        reset_focus_suspend()
        reset_activity()
        return
    end

    -- [집중모드 켜짐/꺼짐 판정]
    -- 토글 모드(2): 버튼이 "방금 눌린 순간"마다 켬/끔을 뒤집습니다.
    -- 홀드 모드(그 외): 버튼을 누르고 있는 동안만 켜진 것으로 취급합니다.
    if cfg.mode == 2 then
        if focus_button_trg() then
            toggle_state = not toggle_state
        end
        focus_active = toggle_state
    else
        focus_active = focus_button_down()
    end

    -- 공격 입력(좌/우클릭 또는 컨트롤러 공격 버튼)의 "방금 눌린 순간"을 감지합니다.
    -- 입력 장치 설정에 따라 마우스 또는 패드 쪽 함수만 호출합니다.
    local attack_trg = false
    attack_held = false
    if cfg.input_device == 2 then
        attack_trg = update_pad_attack_input()
    elseif get_mouse() ~= nil then
        attack_trg = update_attack_input()
    end

    -- 회피 입력은 집중모드 버튼과 무관하게 항상 감지합니다.
    local evade_trg = update_evade_input()

    -- [우선순위 3] 집중모드가 켜진 상태에서 회피 버튼을 "방금" 눌렀으면,
    -- focus_active 자체는 그대로 두고(그래야 HUD가 안 꺼짐) 회전 적용만
    -- 일시정지시킵니다. 이번 프레임은 회전을 적용하지 않고 끝냅니다.
    if focus_active and evade_trg then
        start_focus_suspend()
        reset_activity()
        return
    end

    -- [우선순위 4] 회피로 인한 일시정지 타이머가 아직 남아 있으면, 매 프레임
    -- 경과 시간만큼 깎아 나가고 이번 프레임도 회전을 적용하지 않습니다.
    if focus_is_suspended() then
        focus_suspend_remaining =
            math.max(0.0, focus_suspend_remaining - get_delta_time())
        reset_activity()
        return
    end

    -- [우선순위 5] 집중모드 자체가 꺼져 있으면, 공격 고정 상태를 정리하고
    -- 이번 프레임은 아무것도 하지 않습니다.
    if not focus_active then
        reset_attack_lock()
        reset_activity()
        return
    end

    -- 여기부터는 집중모드가 켜져 있고 회피 일시정지도 아닌 경우입니다.
    -- 정지/이동 판정은 공격 여부와 무관하게 매 프레임 갱신해 둡니다
    -- (이 판정 자체는 "평상시 추적"에만 쓰이고, 공격 고정/handoff에는 영향 없음).
    update_activity()

    -- 매 프레임 현재 무기를 다시 판별해서 다음 공격 시 바로 쓸 수 있게 갱신해 둡니다.
    local player = get_player()
    if player then
        update_weapon_profile(player)
    end

    -- [우선순위 6 시작] 공격 버튼을 "방금" 눌렀으면, 그 순간의 카메라->플레이어
    -- 방향을 계산해서 방향 고정을 새로 시작합니다. 플레이어/카메라 위치가 거의
    -- 겹쳐서(0.0001 미만) 방향을 계산할 수 없는 경우에는 고정을 시작하지 않습니다.
    if attack_trg then
        local player_at_attack = get_player()
        local ptr = get_transform(player_at_attack)
        local ctr = get_camera_transform()

        local ok, err = pcall(function()
            if not player_at_attack or not ptr or not ctr then
                return false
            end

            local ppos = ptr:call("get_Position")
            local cpos = ctr:call("get_Position")

            local dx = ppos.x - cpos.x
            local dz = ppos.z - cpos.z

            if (dx * dx + dz * dz) < 0.0001 then
                return false
            end

            -- 공격을 시작한 순간의 카메라 방향으로 목표 yaw를 고정합니다.
            attack_locked_yaw =
                math.atan(dx, dz) + cfg.yaw_offset

            -- 공격을 시작하는 바로 이 순간의 무기로 고정 시간을 다시 확정합니다(프레임 사이 무기
            -- 교체로 인한 오차 방지).
            update_weapon_profile(player_at_attack)

            -- 고정 유지 시간과 홀드/탭 판정용 타이머를 새로 시작합니다.
            attack_lock_remaining = current_lock_floor()
            attack_hold_elapsed = 0.0
            attack_is_hold = false

            -- 방향 고정을 켜고, 혹시 남아있던 handoff 구간은 취소합니다(고정이 우선).
            attack_lock_active = true
            attack_handoff_remaining = 0.0

            return true
        end)

        if not ok then
            last_error = "attack trigger: " .. tostring(err)
        end
    end

    -- [우선순위 6 계속] 방향 고정이 진행 중인 동안의 처리.
    -- 버튼을 누르고 있는지(attack_held) 여부로 홀드/탭 두 갈래로 나뉩니다.
    if attack_lock_active then
        local dt = get_delta_time()

        -- 누르고 있는 동안: 실제로 누른 시간을 재서 threshold를 넘으면 "홀드"로
        -- 확정하고, 고정 유지 시간이 current_lock_floor() 밑으로 떨어지지 않게
        -- 붙잡아 둡니다(탭 판정용 남은 시간을 소비하지 않음).
        if attack_held then
            attack_hold_elapsed = attack_hold_elapsed + dt
            if attack_hold_elapsed >=
                math.max(0.0, cfg.attack_hold_threshold_seconds or 0.080) then
                attack_is_hold = true
            end

            local floor = current_lock_floor()
            if attack_lock_remaining < floor then
                attack_lock_remaining = floor
            end
        else
            -- 버튼을 뗀 순간, 이미 "홀드"로 확정되어 있었다면 무기별 시간을 더 기다리지 않고 방향
            -- 고정을 즉시 해제합니다.
            if attack_is_hold then
                attack_lock_remaining = 0.0
                attack_lock_active = false
                attack_handoff_remaining = 0.0
                attack_hold_elapsed = 0.0
                attack_is_hold = false
            -- 짧게 눌렀다 뗀 "탭"이었다면, 기존 동작대로 남은 무기별 고정 시간을
            -- 계속 소진한 뒤 0이 되는 순간 고정을 풀고 handoff 구간을 시작합니다.
            else
                attack_lock_remaining =
                    attack_lock_remaining - dt

                if attack_lock_remaining <= 0.0 then
                    attack_lock_remaining = 0.0
                    attack_lock_active = false
                    start_attack_handoff()
                end
            end
        end
    end

    -- [우선순위 7] handoff 구간이 남아 있다면 매 프레임 경과 시간만큼 줄여
    -- 나갑니다(실제로 회전을 적용하는 부분은 8. APPLY 섹션에 있습니다).
    if attack_handoff_remaining > 0.0 then
        attack_handoff_remaining =
            attack_handoff_remaining - get_delta_time()

        if attack_handoff_remaining < 0.0 then
            attack_handoff_remaining = 0.0
        end
    end
end)

--==========================================================================
-- 8. APPLY (실제 회전 적용)
--==========================================================================
-- "평상시 추적"과 handoff가 공통으로 사용하는 목표 방향 계산 함수입니다.
-- 플레이어 기준으로 카메라가 있는 방향(카메라->플레이어 벡터)을 yaw 각도로
-- 구합니다. 두 위치가 거의 겹쳐 있으면(계산 불안정) nil을 반환합니다.
local function get_camera_target_yaw()
    local player = get_player()
    local ptr = get_transform(player)
    local ctr = get_camera_transform()

    if not player or not ptr or not ctr then
        return nil
    end

    local ppos = ptr:call("get_Position")
    local cpos = ctr:call("get_Position")

    local dx = ppos.x - cpos.x
    local dz = ppos.z - cpos.z

    if (dx * dx + dz * dz) < 0.0001 then
        return nil
    end

    return math.atan(dx, dz) + cfg.yaw_offset
end

-- "평상시 추적"에서 사용됩니다. 목표 yaw와 현재 yaw의 차이를 구하고,
-- cfg.smooth 비율만큼만 부드럽게 따라가도록 회전량을 줄입니다. 한 프레임에
-- 회전량이 90도(math.pi*0.5)를 넘지 않도록 제한해서 급격한 튐을 방지합니다.
local function apply_yaw(target_yaw)
    local player = get_player()
    if not player then return end

    local ptr = get_transform(player)
    if not ptr then return end

    local current_rotation = ptr:call("get_Rotation")
    local cur_yaw = yaw_from_quat(current_rotation)
    local diff = wrap_pi(target_yaw - cur_yaw)

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
    local new_rotation =
        (yaw_delta_quat * current_rotation):normalized()

    ptr:call("set_Rotation", new_rotation)
    apply_count = apply_count + 1
end

-- 공격 방향 고정/handoff에서 사용됩니다. smooth를 쓰지 않고 목표 yaw로
-- 즉시(정확하게) 맞춥니다. 차이가 거의 없으면(0.0001 이하) 아무 것도 하지
-- 않아 불필요한 연산을 줄입니다.
local function force_locked_yaw(target_yaw)
    local player = get_player()
    if not player then return end

    local ptr = get_transform(player)
    if not ptr then return end

    local current_rotation = ptr:call("get_Rotation")
    local cur_yaw = yaw_from_quat(current_rotation)
    local diff = wrap_pi(target_yaw - cur_yaw)

    if math.abs(diff) > 0.0001 then
        local yaw_delta_quat = quat_from_yaw(diff)
        local new_rotation =
            (yaw_delta_quat * current_rotation):normalized()

        ptr:call("set_Rotation", new_rotation)
        apply_count = apply_count + 1
    end
end

-- 공격 방향 고정을 실제로 적용하는 함수. 집중모드가 꺼져 있거나 회피로
-- 일시정지 중이거나 apply_rotation이 꺼져 있으면 아무 것도 하지 않습니다.
-- 아래 4개의 후크에서 공통으로 호출됩니다.
local function apply_attack_lock_now()
    if not focus_active then return end
    if focus_is_suspended() then return end
    if not cfg.apply_rotation then return end
    if not attack_lock_active then return end
    if attack_locked_yaw == nil then return end

    local ok, err = pcall(function()
        force_locked_yaw(attack_locked_yaw)
    end)

    if not ok then
        last_error = "attack force apply: " .. tostring(err)
    end
end

-- handoff 구간의 회전 적용. 공격 고정 중에는 호출되지 않으며, Activity Gate와
-- 무관하게(정지 상태여도) 곧바로 현재 카메라 방향으로 이어받습니다.
local function apply_attack_handoff_now()
    if not focus_active then return end
    if focus_is_suspended() then return end
    if not cfg.apply_rotation then return end
    if attack_lock_active then return end
    if attack_handoff_remaining <= 0.0 then return end

    local target_yaw = get_camera_target_yaw()
    if target_yaw == nil then return end

    local ok, err = pcall(function()
        force_locked_yaw(target_yaw)
    end)

    if not ok then
        last_error = "attack handoff apply: " .. tostring(err)
    end
end

-- 평상시 카메라 추적 적용. 공격 고정/handoff 중에는 동작하지 않고,
-- Activity Gate가 켜져 있으면서 캐릭터가 정지 상태일 때도 동작하지 않습니다.
-- 같은 프레임에 이미 한 번 적용했다면(last_apply_frame) 다시 적용하지 않습니다.
local function apply_normal_camera_now()
    if not focus_active then return end
    if focus_is_suspended() then return end
    if not cfg.apply_rotation then return end
    if attack_lock_active then return end
    if attack_handoff_remaining > 0.0 then return end

    if cfg.activity_gate and not activity_active then return end

    local target_yaw = get_camera_target_yaw()
    if target_yaw == nil then return end

    if last_apply_frame == frame_id then
        return
    end

    last_apply_frame = frame_id

    local ok, err = pcall(function()
        apply_yaw(target_yaw)
    end)

    if not ok then
        last_error = "normal apply: " .. tostring(err)
    end
end

-- 아래 4개는 실제로 캐릭터 회전을 게임에 반영하는 후크입니다. 게임이 한
-- 프레임 안에서도 여러 단계에 걸쳐 캐릭터 방향을 자체적으로 다시 쓰기 때문에,
-- 매 단계마다 같은 값을 재적용해야 최종적으로 원하는 방향이 유지됩니다.
--
-- [LockScene 적용 전] 게임이 캐릭터 회전을 계산하기 직전 시점.
-- 공격 고정 중이면 고정 방향을, handoff 중이면 이어받는 방향을, 그 외에는
-- 평상시 추적을 적용합니다.
re.on_pre_application_entry("LockScene", function()
    if not focus_active then return end
    if not cfg.apply_rotation then return end

    if attack_lock_active then
        apply_attack_lock_now()
        return
    end

    if attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
        return
    end

    apply_normal_camera_now()
end)

-- [LockScene 적용 후] 게임이 자체 로직으로 방향을 덮어쓴 직후 다시 강제로 맞춰줍니다(평상시 추적은
-- 여기서 재적용하지 않습니다 - 위 pre 단계에서 이미 처리).
re.on_application_entry("LockScene", function()
    if attack_lock_active then
        apply_attack_lock_now()
    elseif attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
    end
end)

-- [렌더링 준비 전] 렌더링 직전에 카메라/캐릭터 방향이 다시 계산되는 지점이라 한 번 더 맞춰줍니다.
re.on_pre_application_entry("PrepareRendering", function()
    if attack_lock_active then
        apply_attack_lock_now()
    elseif attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
    end
end)

-- [렌더링 준비 후] 마지막으로 한 번 더 확인 후 재적용해서, 화면에 실제로 그려지는 프레임까지 방향이
-- 어긋나지 않게 합니다.
re.on_application_entry("PrepareRendering", function()
    if attack_lock_active then
        apply_attack_lock_now()
    elseif attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
    end
end)

--==========================================================================
-- 9. HUD (화면 중앙 조준경 표시)
--==========================================================================
-- 집중모드가 켜져 있을 때만 화면 중앙보다 살짝 아래에 작은 조준경을
-- 그립니다. 얇은 원형 윤곽선 두 줄이 아니라, 반지름 방향으로 여러 겹의
-- 원호를 겹쳐 그려서 두께가 있는 "띠"처럼 보이게 만듭니다.
-- 아래 상수들은 1080p(세로 1080) 기준 크기이며, draw_focus_hud()에서
-- 화면 세로 해상도에 맞춰 scale로 곱해 조정됩니다.
local FOCUS_RETICLE_Y_RATIO = 0.45
local FOCUS_RETICLE_BASE_RADIUS = 7.5
local FOCUS_RETICLE_GAP_DEG = 11.0
local FOCUS_RETICLE_SEGMENTS = 20
local FOCUS_RETICLE_THICKNESS = 1.95
-- 새로 추가된 상수: 테두리(Outline) 두께. 전체 두께(FOCUS_RETICLE_THICKNESS) 중 일부는 Outline
-- 색으로, 나머지는 Fill 색으로 그립니다.
local FOCUS_RETICLE_OUTLINE_WIDTH = 0.75

-- 새로 추가된 상태: 실제로 그릴 때 쓰는 ABGR 색상값 캐시입니다. 매 프레임 HSB
-- 변환을 다시 계산하지 않고, 설정이 바뀔 때만(바로 아래 refresh_reticle_colors())
-- 갱신합니다 - v4.1.4에서 추가된 캐싱입니다.
local reticle_outline_color = 0xFF000000
local reticle_fill_color = 0xFFFFFFFF

-- cfg에 저장된 HSB 값을 hsb_to_abgr()로 변환해서 위 캐시 변수 2개를 새로
-- 계산합니다. 설정 파일을 불러온 직후(바로 아래) 한 번, 이후로는 UI에서
-- 색상 슬라이더를 조작할 때만 호출됩니다 - 렌더링 중에는 이미 계산된
-- 색상만 사용합니다.
local function refresh_reticle_colors()
    reticle_outline_color = hsb_to_abgr(
        cfg.reticle_outline_h,
        cfg.reticle_outline_s,
        cfg.reticle_outline_b
    )

    reticle_fill_color = hsb_to_abgr(
        cfg.reticle_fill_h,
        cfg.reticle_fill_s,
        cfg.reticle_fill_b
    )
end

-- 설정 파일에서 불러온 HSB 값을 시작 시점에 한 번 색상으로 변환해 둡니다.
refresh_reticle_colors()

-- 중심(cx, cy)에서 start_deg~end_deg 구간에, 두께(thickness)만큼 여러 겹의
-- 원호를 겹쳐 그려 "채워진 띠"처럼 보이게 합니다. 겹치는 선(layers)의 개수는
-- 두께와 화면 배율(scale)에 비례해서 늘어납니다.
local function draw_reticle_arc_band(cx, cy, outer_radius, thickness, start_deg, end_deg, color, scale)
    local start_rad = math.rad(start_deg)
    local end_rad = math.rad(end_deg)
    local segments = math.max(6, FOCUS_RETICLE_SEGMENTS)
    local step = (end_rad - start_rad) / segments

    local layers = math.max(2, math.floor(thickness * 1.8 * scale + 0.5))
    local inner_radius = math.max(0.5, outer_radius - thickness)

    for layer = 0, layers do
        local t = layer / layers
        local radius = outer_radius - (outer_radius - inner_radius) * t

        local prev_x = cx + math.cos(start_rad) * radius
        local prev_y = cy + math.sin(start_rad) * radius

        for i = 1, segments do
            local angle = start_rad + step * i
            local x = cx + math.cos(angle) * radius
            local y = cy + math.sin(angle) * radius

            draw.line(prev_x, prev_y, x, y, color)

            prev_x = x
            prev_y = y
        end
    end
end

-- 새로 추가된 함수: 기존 draw_reticle_arc_band()를 그대로 재사용해서, 같은
-- 자리에 Outline 색으로 한 번(전체 두께), Fill 색으로 한 번(안쪽으로 살짝
-- 줄어든 두께) 겹쳐 그립니다. 그 결과 테두리가 있는 두 가지 색 띠처럼 보입니다.
local function draw_reticle_arc_band_styled(
    cx, cy, outer_radius, thickness, start_deg, end_deg,
    outline_color, fill_color, scale
)
    local outline_width = math.min(
        FOCUS_RETICLE_OUTLINE_WIDTH * scale,
        thickness * 0.45
    )

    draw_reticle_arc_band(
        cx, cy, outer_radius, thickness,
        start_deg, end_deg,
        outline_color, scale
    )

    local fill_thickness = math.max(0.2, thickness - outline_width * 2.0)
    draw_reticle_arc_band(
        cx, cy, outer_radius - outline_width, fill_thickness,
        start_deg, end_deg,
        fill_color, scale
    )
end

-- 매 프레임 호출되어 조준경 전체(좌우 두 개의 원호 + 중앙 점)를 그립니다.
-- 집중모드가 켜져 있거나(focus_active) 회피로 일시정지 중이면
-- (focus_is_suspended) 표시합니다 - 즉 HUD는 회피 중에도 끊기지 않고 계속
-- 보입니다. 화면 해상도(세로 기준, 450 기준값 대비)에 맞춰 크기를 0.75~2.5배
-- 사이로 조정합니다.
local function draw_focus_hud()
    if ((not focus_active) and (not focus_is_suspended())) or not cfg.show_reticle then
        return
    end

    local display = imgui.get_display_size()
    if not display then
        return
    end

    local scale = display.y / 450.0
    if scale < 0.75 then scale = 0.75 end
    if scale > 2.50 then scale = 2.50 end

    local cx = display.x * 0.5
    local cy = display.y * FOCUS_RETICLE_Y_RATIO
    local radius = FOCUS_RETICLE_BASE_RADIUS * scale
    local thickness = math.max(2.8, FOCUS_RETICLE_THICKNESS * scale)
    local gap = FOCUS_RETICLE_GAP_DEG

    -- 새로 추가: 캐시된 Outline/Fill 색상을 가져와서 씁니다(매 프레임 재계산하지 않음).
    local outline_color = reticle_outline_color
    local fill_color = reticle_fill_color

    -- 좌우 각각 gap도(度)만큼 틈을 두고, 아래에서 만든 Outline+Fill 스타일 원호를 그려 좌우가 끊긴
    -- 두 가지 색 띠 형태로 만듭니다.
    draw_reticle_arc_band_styled(
        cx, cy, radius, thickness,
        gap, 180.0 - gap,
        outline_color, fill_color, scale
    )
    draw_reticle_arc_band_styled(
        cx, cy, radius, thickness,
        180.0 + gap, 360.0 - gap,
        outline_color, fill_color, scale
    )

    -- 새로 추가: 중앙 점도 링과 같은 방식으로 Outline 색 원을 먼저 그리고, 그
    -- 위에 약간 작은 Fill 색 원을 겹쳐 그려서 테두리가 있는 점처럼 보이게 합니다.
    local dot_radius = math.max(2.0, 2.4 * scale)
    local dot_outline_width = math.min(
        FOCUS_RETICLE_OUTLINE_WIDTH * scale,
        dot_radius * 0.35
    )

    -- 바깥쪽(Outline) 원을 먼저 그립니다.
    draw.filled_circle(
        cx, cy, dot_radius, outline_color, 16
    )
    -- 그 위에 안쪽(Fill) 원을 덮어 그려서 테두리 효과를 냅니다.
    draw.filled_circle(
        cx, cy, math.max(0.5, dot_radius - dot_outline_width),
        fill_color, 16
    )
end

-- 조준경은 REFramework 설정 창이 닫혀 있어도 계속 보여야 하므로, imgui 메뉴가 아니라 on_frame에서
-- 매 프레임 직접 그립니다.
re.on_frame(function()
    draw_focus_hud()
end)

--==========================================================================
-- 10. UI (REFramework 설정 메뉴)
--==========================================================================
-- REFramework의 스크립트 메뉴 안에 "MHR_FocusMode" 트리 노드로 표시되는
-- 설정 화면입니다. 각 imgui 위젯은 changed(값이 바뀌었는지)와 val(새 값)을
-- 반환하며, changed일 때만 cfg에 반영하고 save_cfg()로 저장합니다.
re.on_draw_ui(function()
    if not imgui.tree_node("MHR_FocusMode") then return end

    -- 위젯들이 공통으로 재사용하는 반환값 변수(값이 바뀌었는지, 새 값이 무엇인지).
    local changed, val

    -- 모드 전체 켜짐/꺼짐 체크박스.
    changed, val = imgui.checkbox("모드 활성화", cfg.enabled)
    if changed then
        cfg.enabled = val
        save_cfg()
    end

    -- 홀드/토글 작동 방식 선택. 방식을 바꾸면 토글 상태와 공격 고정을 안전하게 리셋합니다.
    changed, val = imgui.combo(
        "작동 방식",
        cfg.mode,
        { "홀드 (누르는 동안만)", "토글" }
    )
    if changed then
        cfg.mode = val
        toggle_state = false
        reset_attack_lock()
        save_cfg()
    end

    -- 입력 장치(KBM/컨트롤러) 선택. 장치를 바꾸면 바인딩 캡처를 취소하고, 두 장치가 서로 다른 "직전
    -- 눌림" 상태를 갖고 있으므로 관련 상태를 모두 리셋합니다.
    changed, val = imgui.combo(
        "입력 장치",
        cfg.input_device,
        { "키보드+마우스(KBM)", "컨트롤러" }
    )
    if changed then
        cfg.input_device = val
        binding_target = nil
        focus_prev_down = false
        key_prev_evade = false
        pad_prev_atk1 = false
        pad_prev_atk2 = false
        pad_prev_evade = false
        reset_attack_lock()
        reset_focus_suspend()
        save_cfg()
    end

    -- 컨트롤러 모드일 때는 버튼 4종(집중모드/회피/공격1/공격2)을, KBM 모드일
    -- 때는 키 2종(집중모드/회피)을 각각 보여주고 바꿀 수 있게 합니다. 아래 네
    -- 블록 모두 구조가 동일합니다: 현재 값을 보여주고, 캡처 중이면 안내 문구를,
    -- 아니면 "버튼 변경" 버튼을 표시해서 누르면 binding_target을 설정합니다.
    if cfg.input_device == 2 then
        imgui.text(
            "집중모드 버튼: " ..
            (cfg.pad_key_name ~= "" and pad_display_name(cfg.pad_key_name) or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_focus" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_focus") then
            binding_target = "pad_focus"
        end

        imgui.text(
            "회피 버튼: " ..
            (cfg.pad_evade_name ~= "" and pad_display_name(cfg.pad_evade_name) or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_evade" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_evade") then
            binding_target = "pad_evade"
        end

        imgui.text(
            "공격1 버튼: " ..
            (cfg.pad_atk1_name ~= "" and pad_display_name(cfg.pad_atk1_name) or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_atk1" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_atk1") then
            binding_target = "pad_atk1"
        end

        imgui.text(
            "공격2 버튼: " ..
            (cfg.pad_atk2_name ~= "" and pad_display_name(cfg.pad_atk2_name) or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_atk2" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_atk2") then
            binding_target = "pad_atk2"
        end
    -- KBM 모드: 집중모드 키와 회피 키를 컨트롤러와 같은 방식으로 보여주고 바꿀 수 있게 합니다.
    else
        imgui.text("집중모드 키: " .. key_display_name())
        imgui.same_line()

        if binding_target == "kbm" then
            imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
        elseif imgui.button("키 변경") then
            binding_target = "kbm"
        end

        imgui.text("회피 키: " .. evade_key_display_name())
        imgui.same_line()
        if binding_target == "kbm_evade" then
            imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
        elseif imgui.button("키 변경##kbm_evade") then
            binding_target = "kbm_evade"
        end
    end

    -- 집중모드 조준경(HUD) 표시 여부.
    changed, val = imgui.checkbox(
        "집중모드 조준경 표시",
        cfg.show_reticle
    )
    if changed then
        cfg.show_reticle = val
        save_cfg()
    end

    -- 새로 추가된 UI 블록: 크로스헤어 색상(HSB) 설정입니다. Outline(테두리) 3개,
    -- Fill(안쪽) 3개, 총 6개의 슬라이더로 Hue(색상)/Saturation(채도)/Brightness
    -- (명도)를 각각 조절합니다.
    imgui.separator()
    imgui.text("크로스헤어 색상 (HSB)")
    imgui.text("윤곽선")

    -- 이번 프레임에 슬라이더 중 하나라도 바뀌었는지 표시하는 플래그입니다.
    local reticle_color_changed = false

    -- Outline 색상 슬라이더 3개(H/S/B). 값이 바뀌면 cfg에 반영하고
    -- reticle_color_changed를 true로 표시합니다. 아래 Fill 슬라이더 3개도
    -- 대상 필드만 다를 뿐 완전히 같은 패턴입니다.
    changed, val = imgui.slider_float(
        "H##reticle_outline_h",
        cfg.reticle_outline_h, 0.0, 360.0, "%.0f°"
    )
    if changed then
        cfg.reticle_outline_h = val
        reticle_color_changed = true
    end

    changed, val = imgui.slider_float(
        "S##reticle_outline_s",
        cfg.reticle_outline_s, 0.0, 100.0, "%.1f%%"
    )
    if changed then
        cfg.reticle_outline_s = val
        reticle_color_changed = true
    end

    changed, val = imgui.slider_float(
        "B##reticle_outline_b",
        cfg.reticle_outline_b, 0.0, 100.0, "%.1f%%"
    )
    if changed then
        cfg.reticle_outline_b = val
        reticle_color_changed = true
    end

    -- 여기부터 Fill(안쪽) 색상 슬라이더 3개(패턴은 위 Outline과 동일).
    imgui.text("채움")

    changed, val = imgui.slider_float(
        "H##reticle_fill_h",
        cfg.reticle_fill_h, 0.0, 360.0, "%.0f°"
    )
    if changed then
        cfg.reticle_fill_h = val
        reticle_color_changed = true
    end

    changed, val = imgui.slider_float(
        "S##reticle_fill_s",
        cfg.reticle_fill_s, 0.0, 100.0, "%.1f%%"
    )
    if changed then
        cfg.reticle_fill_s = val
        reticle_color_changed = true
    end

    changed, val = imgui.slider_float(
        "B##reticle_fill_b",
        cfg.reticle_fill_b, 0.0, 100.0, "%.1f%%"
    )
    if changed then
        cfg.reticle_fill_b = val
        reticle_color_changed = true
    end

    -- 슬라이더를 움직인 프레임에만 HSB -> ABGR 변환을 다시 수행하고
    -- (refresh_reticle_colors), 그 결과를 설정 파일에도 저장합니다. 즉 실제
    -- 렌더링(draw_focus_hud)에서는 매 프레임 이 변환을 반복하지 않습니다.
    if reticle_color_changed then
        refresh_reticle_colors()
        save_cfg()
    end

    -- 디버그 표시 여부. 켜면 아래에 내부 상태값 패널이 나타납니다.
    changed, val = imgui.checkbox(
        "디버그 표시",
        cfg.debug
    )
    if changed then
        cfg.debug = val
        save_cfg()
    end

    -- 디버그 패널. 문제가 생겼을 때 어느 단계에서 막혔는지 확인하기 위한
    -- 내부 상태값들을 그대로 노출합니다. update_weapon_profile을 한 번 더
    -- 호출해서 표시 시점 기준 최신 무기 정보를 보여줍니다.
    if cfg.debug then
        update_weapon_profile(get_player())

        imgui.text(
            "input_device: " ..
            (cfg.input_device == 2 and "컨트롤러" or "KBM")
        )
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text(
            "focus suspend remaining: " ..
            string.format("%.3f초", focus_suspend_remaining)
        )
        imgui.text(
            "evade bind: " ..
            (cfg.input_device == 2
                and pad_display_name(cfg.pad_evade_name or "")
                or evade_key_display_name())
        )
        imgui.text(
            "activity_active: " ..
            tostring(activity_active) ..
            " (gate=" .. tostring(cfg.activity_gate) .. ")"
        )
        imgui.text(
            "activity_frames_left: " ..
            tostring(activity_frames_left)
        )
        -- 공격 방향 고정/홀드 판정 관련 상태.
        imgui.text("attack lock: " .. tostring(attack_lock_active))
        imgui.text("attack_held(홀드 중): " .. tostring(attack_held))
        imgui.text("attack_is_hold: " .. tostring(attack_is_hold))
        imgui.text(
            "attack hold elapsed: " ..
            string.format("%.3f초", attack_hold_elapsed)
        )
        imgui.text(
            "hold threshold: " ..
            string.format(
                "%.3f초",
                math.max(0.0, cfg.attack_hold_threshold_seconds or 0.080)
            )
        )
        imgui.text(
            "attack remaining: " ..
            string.format("%.3f초", attack_lock_remaining)
        )
        imgui.text(
            "handoff remaining: " ..
            string.format("%.3f초", attack_handoff_remaining)
        )
        -- 무기 판별 결과 관련 상태.
        imgui.text("BFM Type: " .. tostring(bfm_type_name))
        imgui.text(
            "weapon: " ..
            tostring(
                WEAPON_LABELS[current_weapon_key] or
                current_weapon_key
            )
        )
        imgui.text(
            "weapon window: " ..
            string.format("%.3f초", current_window_seconds)
        )
        imgui.text(
            "apply_count: " ..
            tostring(apply_count)
        )

        -- 각 영역에서 마지막으로 발생한 오류 메시지들(있을 때만 표시).
        if weapon_detect_error then
            imgui.text("weapon error: " .. weapon_detect_error)
        end
        if input_error then
            imgui.text("input error: " .. input_error)
        end
        if mouse_error then
            imgui.text("mouse error: " .. mouse_error)
        end
        if pad_error then
            imgui.text("pad error: " .. pad_error)
        end
        if last_error then
            imgui.text("last error: " .. last_error)
        end
        -- 새로 추가: 설정 저장 실패 메시지를 표시합니다(1번 섹션 save_cfg() 참고).
        if cfg_save_error then
            imgui.text("config save error: " .. cfg_save_error)
        end
    end

    -- tree_node로 연 트리를 닫아줍니다(위쪽 tree_node 호출과 짝).
    imgui.tree_pop()
end)

--==========================================================================
-- 11. 로드 완료 로그
--==========================================================================
-- REFramework 콘솔에 로드 완료와 주요 설정값을 한 번 출력합니다(문제 발생 시 초기 상태 확인용).
log.info(
    "[MHR_FocusMode v4.3.0] loaded. " ..
    "BFM-type-only weapon detection, instant hold-release + HSB outline/fill HUD reticle + controller input" ..
    ", activity_gate=" ..
    tostring(cfg.activity_gate) ..
    ", input_device=" ..
    (cfg.input_device == 2 and "controller" or "kbm") ..
    ", key=" ..
    tostring(key_display_name()) ..
    ", lock_extension=" ..
    tostring(cfg.attack_lock_extension_seconds or 0.0) ..
    ", handoff=" ..
    tostring(cfg.attack_handoff_seconds or 0.0) ..
    ", evade_suspend=" ..
    tostring(cfg.evade_focus_suspend_seconds or 0.700) ..
    ", evade_kbm=" ..
    tostring(evade_key_display_name()) ..
    ", evade_pad=" ..
    tostring(cfg.pad_evade_name or "")
)

--[[
    변경 이력 (요약)

    v4.1.4 : HSB -> ABGR 색상 변환을 색상 설정이 바뀐 순간에만 수행하도록
             캐시했습니다. 크로스헤어 자체는 이전처럼 매 프레임 그립니다.

    v4.1.2 : 크로스헤어의 Outline(테두리)과 Fill(안쪽) 색상을 분리했고,
             REFramework UI에서 각각 HSB로 조절할 수 있게 되었습니다.

    (참고: 이 파일에는 설정 저장 실패를 감지하는 안전장치(cfg_save_error)도
     추가되어 있지만, 소스 헤더에 이 변경에 대한 버전 기록은 없습니다.
     로그 메시지 기준 현재 버전은 v4.3.0으로 표기되어 있습니다.)

    v4.1.1 : 회피로 인한 회전 일시정지 중에도 크로스헤어(HUD)는 계속 표시.

    v4.1   : 회피 버튼 추가 (KBM/컨트롤러 별도 바인딩, 기본 Space / RDown).
             회피 시 회전 적용을 설정 시간(기본 0.7초)만큼 중단 후 자동 복구.
             회피 중에는 공격 고정/handoff도 회전을 덮어쓰지 않도록 차단.

    v4.0   : 입력 장치를 KBM/컨트롤러 중 선택 가능. 컨트롤러의 집중모드/공격1/
             공격2 버튼을 직접 바인딩 가능. 컨트롤러 공격 버튼은 좌우클릭과
             동일하게 취급되어 기존 탭/홀드/무기별 고정/handoff 로직을 그대로
             공유. (via.hid.GamePad API는 비공식이라 버전에 따라 동작 안 할 수 있음)

    v3.3   : 좌/우클릭 홀드 공격은 버튼을 뗀 즉시 방향 고정 해제(무기별 대기 없음).
             짧은 탭은 기존처럼 무기별 시간만큼 고정 후 handoff.
             HUD를 텍스트/사각형에서 화면 중앙 조준경(reticle)으로 변경.

    v3.1   : v1.8의 Activity Gate(정지 판정)를 복원. 평상시 추적에만 적용되고,
             공격 고정/handoff는 정지 여부와 무관하게 항상 동작.

    v3.0   : 공격 입력 순간의 카메라 방향을 저장하고 BFM Type 하나로만 무기를
             자동 판별(다른 무기 탐색/수동 선택 없음). 매칭 실패 시에만 Generic
             Timing 사용. 공격 고정 중에는 smooth 없이 정확한 yaw 강제.
             LockScene/PrepareRendering 전후 4곳에서 재적용. 공격 직후 handoff
             구간 유지. v2.5의 BFM setter/getter 탐색 제거(Type 하나만 사용).
--]]
