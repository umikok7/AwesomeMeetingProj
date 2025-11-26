-- KEYS[1]: chat:seq:{room_sid} (String - 序列号计数器)
-- KEYS[2]: chat:sorted:{room_sid} (ZSet - score:seq, member:完整消息JSON)
-- KEYS[3]: chat:uuid:{room_sid} (Hash - field:uuid, value:seq，用于幂等性检查)
-- KEYS[4]: chat:rooms:sync (Set - 待同步房间集合)
-- ARGV[1]: message_json (完整消息JSON - 明文，落库时再加密)
-- ARGV[2]: uuid (消息唯一ID)
-- ARGV[3]: ttl_seconds (幂等Key的过期时间，单位：秒)
-- ARGV[4]: room_sid (房间SID，用于标记)
-- 1. 幂等性检查：uuid是否已存在
local existing_seq = redis.call('HGET', KEYS[3], ARGV[2])
if existing_seq then
    return {'DUPLICATE', existing_seq}
end
-- 2. 原子化递增seq
local new_seq = redis.call('INCR', KEYS[1])
-- 3. 存储uuid->seq映射（用于幂等性检查）
redis.call('HSET', KEYS[3], ARGV[2], new_seq)
-- 4. 更新JSON中的seq字段 (使用Redis内置的cjson)
local msg_obj = cjson.decode(ARGV[1])
msg_obj.seq = new_seq
local updated_json = cjson.encode(msg_obj)
-- 5. 将更新后的消息JSON存入ZSet（score=seq, member=JSON）
redis.call('ZADD', KEYS[2], new_seq, updated_json)
-- 6. 将房间标记为待同步（写前标记）
redis.call('SADD', KEYS[4], ARGV[4])
-- 7. 刷新幂等性检查key的TTL
redis.call('EXPIRE', KEYS[3], tonumber(ARGV[3]))
-- 8. 返回新seq
return {'OK', tostring(new_seq)}