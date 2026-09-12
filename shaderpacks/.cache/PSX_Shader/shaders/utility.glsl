vec2 wrap(vec2 value, vec2 min, vec2 max) {
    vec2 range = max - min;
    return mod(value - min, range) + min;
}

vec2 wrapMirror(vec2 value, vec2 min, vec2 max) {
    vec2 range = max - min;

    vec2 value_o = mod(value - min, range) + min;
    if (value.x > max.x || value.x < min.x) {
        value_o.x = -mod(value - max, range).x + max.x;
    }
    if (value.y > max.y || value.y < min.y) {
        value_o.y = -mod(value - max, range).y + max.y;
    }
    return value_o;
}