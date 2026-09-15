-- 静态玩法配置。
-- ConfigService 通过 sharedata 发布此表，避免每个 Lua VM 都保存一份大型配置的深拷贝。
return {
    scenes = {
        [1] = {
            id = 1,
            name = "Learning Meadow",
            grid_size = 20,
            view_radius = 18,
            attack_range = 5,
            -- Scene 使用这些值做服务端权威移动校验；单位分别为坐标单位/秒和秒。
            min_x = 0,
            max_x = 200,
            min_y = 0,
            max_y = 200,
            move_speed = 10,
            move_burst_seconds = 1,
            monsters = {
                { id = 100001, name = "Green Slime", x = 104, y = 100, hp = 50, respawn_ticks = 500 },
                { id = 100002, name = "Forest Wolf", x = 115, y = 104, hp = 80, respawn_ticks = 800 },
                { id = 100003, name = "Training Golem", x = 125, y = 100, hp = 140, respawn_ticks = 1000 },
            },
        },
    },
}
