-- Sproto schemas used by both server and learning client.
-- Keep schema text free of Lua comments because sprotoparser parses the raw text.
local M = {}

M.c2s = [[
.package {
    type 0 : integer
    session 1 : integer
}

login 1 {
    request {
        player_id 0 : integer
        token 1 : string
    }
    response {
        code 0 : integer
        message 1 : string
        player_id 2 : integer
        name 3 : string
        level 4 : integer
        gold 5 : integer
        hp 6 : integer
        max_hp 7 : integer
        scene_id 8 : integer
        x 9 : integer
        y 10 : integer
    }
}

ping 2 {
    request {}
    response {
        code 0 : integer
        server_time 1 : integer
    }
}

move 3 {
    request {
        x 0 : integer
        y 1 : integer
    }
    response {
        code 0 : integer
        message 1 : string
        x 2 : integer
        y 3 : integer
    }
}

attack 4 {
    request {
        target_id 0 : integer
    }
    response {
        code 0 : integer
        message 1 : string
        target_id 2 : integer
        target_hp 3 : integer
        dead 4 : boolean
    }
}

logout 5 {
    request {}
    response {
        code 0 : integer
    }
}
]]

M.s2c = [[
.package {
    type 0 : integer
    session 1 : integer
}

entity_enter 1 {
    request {
        entity_type 0 : integer
        entity_id 1 : integer
        name 2 : string
        x 3 : integer
        y 4 : integer
        hp 5 : integer
        max_hp 6 : integer
    }
}

entity_leave 2 {
    request {
        entity_type 0 : integer
        entity_id 1 : integer
    }
}

entity_move 3 {
    request {
        entity_type 0 : integer
        entity_id 1 : integer
        x 2 : integer
        y 3 : integer
    }
}

entity_hp 4 {
    request {
        entity_type 0 : integer
        entity_id 1 : integer
        hp 2 : integer
        max_hp 3 : integer
    }
}

monster_dead 5 {
    request {
        monster_id 0 : integer
        killer_id 1 : integer
    }
}

system_message 6 {
    request {
        text 0 : string
    }
}

kick 7 {
    request {
        reason 0 : string
    }
}
]]

return M
