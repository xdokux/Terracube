// 黑白
vec4 grayscale(vec4 inputColor) {
    float average = (inputColor.r + inputColor.g + inputColor.b) / 3.0;
    return vec4(vec3(average), inputColor.a);
}

// 复古
vec4 sepia(vec4 inputColor) {
    float average = (inputColor.r + inputColor.g + inputColor.b) / 2.6;
    return vec4(average + 0.15, average + 0.075, average, inputColor.a);
}

// 凋零
vec4 wither(vec4 inputColor) {
    vec3 color = inputColor.rgb;
    vec3 wither[5];
    wither[0] = vec3(30.0, 33.0, 42.0)/255.0;     // #1e212a
    wither[1] = vec3(53.0, 41.0, 57.0)/255.0;     // #352939
    wither[2] = vec3(110.0, 49.0, 74.0)/255.0;    // #6e314a
    wither[3] = vec3(168.0, 52.0, 79.0)/255.0;    // #a8344f
    wither[4] = vec3(221.0, 50.0, 71.0)/255.0;    // #dd3247

    float minDistance = 1e20;
    int closestIndex = 0;
    for (int i = 0; i < 5; i++) {
        float d = distance(color, wither[i]);
        if (d < minDistance) {
            minDistance = d;
            closestIndex = i;
        }
    }
    vec3 resultColor = wither[closestIndex];

    return vec4(resultColor, inputColor.a);
}

// 彩色复古
vec4 CL8UDS(vec4 inputColor) {
    vec3 color = floor(inputColor.rgb * 255.0 + 0.5) / 255.0;
    vec3 CL8UDS[8];
    CL8UDS[0] = vec3(252.0, 176.0, 140.0)/255.0;
    CL8UDS[1] = vec3(239.0, 157.0, 127.0)/255.0;
    CL8UDS[2] = vec3(214.0, 147.0, 138.0)/255.0;
    CL8UDS[3] = vec3(180.0, 141.0, 146.0)/255.0;
    CL8UDS[4] = vec3(165.0, 151.0, 161.0)/255.0;
    CL8UDS[5] = vec3(143.0, 160.0, 191.0)/255.0;
    CL8UDS[6] = vec3(154.0, 171.0, 201.0)/255.0;
    CL8UDS[7] = vec3(165.0, 183.0, 212.0)/255.0;


    float brightness = dot(color, vec3(0.299, 0.587, 0.114));
    int brightnessLevel = int(floor(brightness * 47.0 + 0.5));
    brightnessLevel = clamp(brightnessLevel, 0, 31);
    float targetBrightness = float(brightnessLevel) / 31.0;
    float minDistance = 1e20;
    vec3 resultColor = color;
    for (int i = 0; i < 8; i++) {
        float baseBrightness = dot(CL8UDS[i], vec3(0.299, 0.587, 0.114));
        vec3 adjustedColor = CL8UDS[i] * (targetBrightness / baseBrightness);
        adjustedColor = clamp(adjustedColor, 0.0, 1.0);

        float d = distance(color, adjustedColor);
        if (d < minDistance) {
            minDistance = d;
            resultColor = adjustedColor;
        }
    }

    return vec4(resultColor, inputColor.a);
}


// 测试
vec4 QAQ(vec4 inputColor) {
    float gray = dot(inputColor.rgb, vec3(0.299, 0.587, 0.114));
    const vec3 darkColor = vec3(31.0, 34.0, 52.0) / 255.0;
    const vec3 lightColor = vec3(255.0, 250.0, 240.0) / 255.0;
    float level = floor(gray * 3.0 + 0.5);
    float t = level / 3.0;
    vec3 resultColor = mix(darkColor, lightColor, t);

    return vec4(resultColor, inputColor.a);
}