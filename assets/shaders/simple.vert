#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec4 in_color;

layout(location = 0) out vec3 out_position;
layout(location = 1) out vec3 out_normal;
layout(location = 2) out vec4 out_color;

void main() {
    mat4 view_model = ubo.view * ubo.model;
    mat4 proj_view_model =  ubo.projection * view_model;

    gl_Position = proj_view_model * vec4(in_position, 1.0);
    out_position = (view_model * vec4(in_position, 1.0)).xyz;
    out_normal = (ubo.model * vec4(in_normal, 0.0)).xyz;
    out_color = in_color;
}
