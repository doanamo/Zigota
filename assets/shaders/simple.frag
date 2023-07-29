#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec4 in_color;
layout(location = 0) out vec4 out_color;

void main() {
    vec3 normal = normalize(in_normal);
    vec3 view_dir = normalize(-in_position);

    vec3 light_color = vec3(1.0, 1.0, 1.0);
    vec3 light_dir = normalize(vec3(-1.0, 0.5, 0.0));
    vec3 light_reflection = reflect(light_dir, normal);

    float ambient_factor = 0.005;
    vec3 ambient = light_color * ambient_factor;

    float diffuse_factor = max(dot(normal, -light_dir), 0.0);
    vec3 diffuse = light_color * diffuse_factor;

    float specular_strenth = 0.5;
    float specular_factor = pow(max(dot(view_dir, light_reflection), 0.0), 32.0);
    vec3 specular = light_color * specular_factor * specular_strenth;

    out_color = in_color * vec4(ambient + diffuse + specular, 1.0);
}
